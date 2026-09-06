// A browser dashboard for the app, served over HTTP so a phone or another
// computer on the same network — or, through a Cloudflare tunnel, anywhere —
// can drive the VM backend without the desktop UI. Pro-gated.
//
// Unlike the MCP server (loopback only) this one binds to every interface on
// purpose: being reachable from other devices is the whole point. What
// protects it is the access token, carried in the URL the QR code encodes
// (`?token=...`) so a scan is all it takes to get in, and checked on every
// request. The page itself is embedded in the binary (web_dashboard_page.dart)
// so the dashboard needs no internet access and no files on disk.
//
// The dashboard drives the backend through the same tool set the MCP server
// exposes (buildWslMcpTools), plus a thin JSON layer for the instance list
// and the start/stop/duplicate buttons, so the two surfaces cannot drift
// apart.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:wsl2distromanager/api/apple/apple_vm_api.dart';
import 'package:wsl2distromanager/api/mcp/cloudflare_tunnel_service.dart';
import 'package:wsl2distromanager/api/mcp/mcp_server.dart';
import 'package:wsl2distromanager/api/mcp/wsl_mcp_tools.dart';
import 'package:wsl2distromanager/api/mcp/wsl_terminal_manager.dart';
import 'package:wsl2distromanager/api/quick_actions.dart';
import 'package:wsl2distromanager/api/vm/vm_backend.dart';
import 'package:wsl2distromanager/api/vm/vm_platform.dart';
import 'package:wsl2distromanager/api/web/web_dashboard_page.dart';
import 'package:wsl2distromanager/components/constants.dart';
import 'package:wsl2distromanager/components/helpers.dart';

typedef DashboardServerFactory = Future<HttpServer> Function(
    Handler handler, Object address, int port);

/// Enumerates the host's network interfaces; tests inject a fixed answer.
typedef NetworkInterfaceLister = Future<List<NetworkInterface>> Function();

Future<HttpServer> _defaultServerFactory(
    Handler handler, Object address, int port) {
  return io.serve(handler, address, port);
}

Future<List<NetworkInterface>> _defaultInterfaceLister() {
  return NetworkInterface.list(
      includeLoopback: false, type: InternetAddressType.IPv4);
}

class WebDashboardService {
  static const int port = 59134;

  /// Query parameter and header the token travels in.
  static const String tokenParam = 'token';
  static const String tokenHeader = 'x-dashboard-token';

  // Static like WslMcpService._server: every WebDashboardService() must agree
  // on the one real server and its terminal sessions.
  static HttpServer? _server;
  static WslTerminalManager? _terminalManager;

  final VmBackend backend;
  final DashboardServerFactory serverFactory;
  final CloudflareTunnelService tunnel;
  final NetworkInterfaceLister interfaceLister;

  WebDashboardService({
    VmBackend? backend,
    DashboardServerFactory? serverFactory,
    CloudflareTunnelService? tunnel,
    NetworkInterfaceLister? interfaceLister,
  })  : backend = backend ?? vmBackend(),
        serverFactory = serverFactory ?? _defaultServerFactory,
        tunnel = tunnel ?? CloudflareTunnelService(localPort: port),
        interfaceLister = interfaceLister ?? _defaultInterfaceLister;

  bool get isRunning => _server != null;

  bool get enabled => prefs.getBool('WebDashboardEnabled') ?? false;

  /// The token every request must carry. Generated on first use and
  /// persisted; [regenerateToken] rotates it, which invalidates every link
  /// and QR code handed out so far.
  String get token {
    final existing = prefs.getString('WebDashboardToken');
    if (existing != null && existing.isNotEmpty) return existing;
    return regenerateToken();
  }

  String regenerateToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    final newToken = base64Url.encode(bytes).replaceAll('=', '');
    prefs.setString('WebDashboardToken', newToken);
    return newToken;
  }

  /// The full dashboard link for one reachable address: scheme, host, port
  /// and the token as a query parameter, ready for a QR code.
  String urlFor(String host) {
    final bracketed = host.contains(':') ? '[$host]' : host;
    return 'http://$bracketed:$port/?$tokenParam=$token';
  }

  /// The link for this machine only.
  String get localUrl => urlFor('127.0.0.1');

  /// IPv4 addresses other devices on the network can reach this host at,
  /// private ranges first so the QR code defaults to the home/office LAN.
  Future<List<String>> lanAddresses() async {
    List<NetworkInterface> interfaces;
    try {
      interfaces = await interfaceLister();
    } catch (_) {
      return const [];
    }
    final addresses = <String>[];
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        if (addr.type != InternetAddressType.IPv4) continue;
        if (addr.isLoopback || addr.isLinkLocal) continue;
        if (!addresses.contains(addr.address)) addresses.add(addr.address);
      }
    }
    addresses.sort((a, b) {
      final rank = _privateRank(a).compareTo(_privateRank(b));
      return rank != 0 ? rank : a.compareTo(b);
    });
    return addresses;
  }

  static int _privateRank(String address) {
    if (address.startsWith('192.168.')) return 0;
    if (address.startsWith('10.')) return 1;
    final parts = address.split('.');
    final second = parts.length > 1 ? int.tryParse(parts[1]) : null;
    if (address.startsWith('172.') &&
        second != null &&
        second >= 16 &&
        second <= 31) {
      return 2;
    }
    return 3;
  }

  /// Dashboard links for every LAN address, in [lanAddresses] order.
  Future<List<String>> shareUrls() async =>
      [for (final address in await lanAddresses()) urlFor(address)];

  /// The public link once the tunnel is up, or null.
  String? get tunnelUrl {
    final base = tunnel.publicUrl;
    if (base == null) return null;
    return '$base/?$tokenParam=$token';
  }

  /// Publishes the dashboard through a Cloudflare quick tunnel and returns
  /// the public link. Throws when cloudflared cannot be run.
  Future<String> startTunnel() async {
    await tunnel.start();
    return tunnelUrl!;
  }

  Future<void> stopTunnel() => tunnel.stop();

  /// Persists the preference and starts or stops the server. A failed start
  /// leaves the preference off, so the next launch does not retry a port
  /// that is known to be taken.
  Future<void> setEnabled(bool value) async {
    prefs.setBool('WebDashboardEnabled', value);
    if (!value) {
      await stop();
      return;
    }
    try {
      await start();
    } catch (_) {
      prefs.setBool('WebDashboardEnabled', false);
      rethrow;
    }
  }

  /// Binds the server. Throws when the port cannot be bound so the Settings
  /// UI can say so instead of showing a link nothing listens on.
  Future<void> start() async {
    if (isRunning) return;

    _terminalManager = WslTerminalManager(wslApi: backend);
    final tools = buildWslMcpTools(backend, _terminalManager!);
    final handler = const Pipeline()
        .addMiddleware(_authMiddleware(() => token))
        .addHandler((request) => _route(request, tools));

    try {
      // Every interface on purpose — see the file comment.
      _server = await serverFactory(handler, '0.0.0.0', port);
    } catch (_) {
      _server = null;
      await _terminalManager?.closeAll();
      _terminalManager = null;
      rethrow;
    }
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    await _terminalManager?.closeAll();
    _terminalManager = null;
    // A public URL routing to a dead server is worse than no URL.
    await tunnel.stop();
  }

  Future<Response> _route(Request request, List<McpTool> tools) async {
    final segments = request.url.pathSegments;

    if (segments.isEmpty || segments.first == 'index.html') {
      if (request.method != 'GET') return _methodNotAllowed();
      return Response.ok(webDashboardHtml, headers: {
        'content-type': 'text/html; charset=utf-8',
        'cache-control': 'no-store',
      });
    }

    if (segments.first != 'api') return _notFound();
    final rest = segments.sublist(1);

    if (rest.length == 1 && rest.first == 'state') {
      if (request.method != 'GET') return _methodNotAllowed();
      return _json(await _state(tools));
    }

    if (rest.length == 1 && rest.first == 'tools') {
      if (request.method != 'GET') return _methodNotAllowed();
      return _json({
        'tools': [
          for (final tool in tools)
            {
              'name': tool.name,
              'description': tool.description,
              'inputSchema': tool.inputSchema,
            }
        ],
      });
    }

    if (rest.length == 2 && rest.first == 'tools') {
      if (request.method != 'POST') return _methodNotAllowed();
      McpTool? tool;
      for (final candidate in tools) {
        if (candidate.name == rest[1]) {
          tool = candidate;
          break;
        }
      }
      if (tool == null) return _notFound();
      final Map<String, dynamic> arguments;
      try {
        final body = await request.readAsString();
        final decoded = body.trim().isEmpty ? {} : json.decode(body);
        final raw = decoded is Map ? decoded['arguments'] : null;
        arguments = raw is Map ? Map<String, dynamic>.from(raw) : {};
      } catch (_) {
        return _json({'ok': false, 'error': 'Invalid JSON body'},
            status: 400);
      }
      try {
        final text = await tool.handler(arguments);
        return _json({'ok': true, 'text': text});
      } catch (e) {
        return _json({'ok': false, 'error': e.toString()});
      }
    }

    if (rest.length == 1 && rest.first == 'shutdown') {
      if (request.method != 'POST') return _methodNotAllowed();
      return _attempt(() => backend.shutdown());
    }

    if (rest.length == 3 && rest.first == 'instances') {
      if (request.method != 'POST') return _methodNotAllowed();
      final name = rest[1];
      switch (rest[2]) {
        case 'start':
          return _attempt(() => _startInstance(name));
        case 'stop':
          return _attempt(() => backend.stop(name));
        case 'copy':
          final String newName;
          try {
            final decoded = json.decode(await request.readAsString());
            newName = decoded is Map ? '${decoded['new_name'] ?? ''}' : '';
          } catch (_) {
            return _json({'ok': false, 'error': 'Invalid JSON body'},
                status: 400);
          }
          if (newName.trim().isEmpty) {
            return _json({'ok': false, 'error': 'new_name is required'},
                status: 400);
          }
          return _attempt(() => backend.copy(name, newName.trim()));
      }
    }

    return _notFound();
  }

  /// Brings an instance up without opening anything on the host: the person
  /// clicking is on another device, so a terminal window here helps nobody.
  Future<void> _startInstance(String name) async {
    final api = backend;
    if (api is AppleVmApi) {
      await api.startHeadless(name);
      return;
    }
    // Running any command starts a stopped WSL distro.
    await backend.execCmdAsRoot(name, 'true');
  }

  Future<Map<String, dynamic>> _state(List<McpTool> tools) async {
    final features = backend.features;
    Instances instances;
    String? error;
    try {
      instances = await backend.list(false);
    } catch (e) {
      instances = backend.lastDistroList;
      error = e.toString();
    }
    final sessions = _terminalManager?.sessions ?? const [];
    return {
      'host': {
        'name': _hostName(),
        'platform': Platform.operatingSystem,
        'version': currentVersion,
        'backend': backend.backendId,
        'instanceNoun': backend.instanceNoun,
        'remote': backend.isRemote,
        'remoteLabel': backend.remoteLabel,
        'features': {
          'wslConfig': features.wslConfig,
          'quickActions': features.quickActions,
          'packaging': features.packaging,
          'mountDisk': features.mountDisk,
          'cleanup': features.cleanup,
          'createVm': features.createVm,
          'templatesDeprecated': features.templatesDeprecated,
        },
        'toolCount': tools.length,
      },
      if (error != null) 'error': error,
      'instances': [
        for (final name in instances.all)
          {
            'name': name,
            'running': instances.running.contains(name),
            'meta': backend.instanceMetaLabel(name),
            'path': _safe(() => backend.currentDistroPath(name)),
          }
      ],
      'sessions': [
        for (final s in sessions)
          {
            'id': s.id,
            'distro': s.distribution,
            'user': s.user,
            'alive': s.isAlive,
            'startedAt': s.startedAt.toIso8601String(),
          }
      ],
      'snippets': features.quickActions
          ? [
              for (final item in _safe(() => QuickAction().getFromPrefs()) ??
                  const <QuickActionItem>[])
                {'name': item.name, 'content': item.content}
            ]
          : const [],
    };
  }

  static String _hostName() {
    try {
      return Platform.localHostname;
    } catch (_) {
      return '';
    }
  }

  static T? _safe<T>(T Function() read) {
    try {
      return read();
    } catch (_) {
      return null;
    }
  }

  Future<Response> _attempt(Future<Object?> Function() action) async {
    try {
      final result = await action();
      return _json({'ok': true, 'text': result?.toString() ?? ''});
    } catch (e) {
      return _json({'ok': false, 'error': e.toString()});
    }
  }

  static Response _json(Map<String, dynamic> body, {int status = 200}) =>
      Response(status,
          body: json.encode(body),
          headers: {
            'content-type': 'application/json; charset=utf-8',
            'cache-control': 'no-store',
          });

  static Response _notFound() =>
      _json({'ok': false, 'error': 'Not found'}, status: 404);

  static Response _methodNotAllowed() =>
      _json({'ok': false, 'error': 'Method not allowed'}, status: 405);

  /// Accepts the token as `?token=`, `X-Dashboard-Token` or a bearer header.
  /// The page keeps it in the URL so a shared link or QR code keeps working.
  Middleware _authMiddleware(String Function() expectedToken) {
    return (Handler innerHandler) {
      return (Request request) {
        final expected = expectedToken();
        final candidates = <String?>[
          request.url.queryParameters[tokenParam],
          request.headers[tokenHeader],
          _bearer(request.headers['authorization']),
        ];
        final ok = candidates.any((c) => c != null && _sameToken(c, expected));
        if (ok) return innerHandler(request);

        final wantsHtml = request.url.pathSegments.isEmpty ||
            request.url.pathSegments.first != 'api';
        if (wantsHtml) {
          return Response(403,
              body: webDashboardUnauthorizedHtml,
              headers: {'content-type': 'text/html; charset=utf-8'});
        }
        return _json({'ok': false, 'error': 'Unauthorized'}, status: 403);
      };
    };
  }

  static String? _bearer(String? header) {
    if (header == null) return null;
    const prefix = 'Bearer ';
    return header.startsWith(prefix) ? header.substring(prefix.length) : null;
  }

  /// Constant-time comparison so response timing leaks nothing about the
  /// token — cheap insurance on an endpoint that faces the network.
  static bool _sameToken(String given, String expected) {
    final a = utf8.encode(given);
    final b = utf8.encode(expected);
    var diff = a.length ^ b.length;
    for (var i = 0; i < a.length && i < b.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
