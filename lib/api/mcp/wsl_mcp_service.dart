// Local HTTP endpoint exposing the WSL API to MCP clients. Pro-gated.
//
// It can run arbitrary commands, so it binds to 127.0.0.1 only (never the
// LAN, unlike the distro-sync server in components/sync.dart) and requires
// a bearer token on every request.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:wsl2distromanager/api/mcp/cloudflare_tunnel_service.dart';
import 'package:wsl2distromanager/api/mcp/mcp_server.dart';
import 'package:wsl2distromanager/api/mcp/wsl_mcp_tools.dart';
import 'package:wsl2distromanager/api/mcp/wsl_terminal_manager.dart';
import 'package:wsl2distromanager/api/wsl.dart';
import 'package:wsl2distromanager/components/constants.dart';
import 'package:wsl2distromanager/components/helpers.dart';

typedef McpServerFactory = Future<HttpServer> Function(
    Handler handler, Object address, int port);

Future<HttpServer> _defaultMcpServerFactory(
    Handler handler, Object address, int port) {
  return io.serve(handler, address, port);
}

class WslMcpService {
  static const int port = 59133;
  static const String path = '/mcp';

  // Static: callers construct a fresh WslMcpService() wherever they need
  // one, but all of them must agree on the single running server and its
  // sessions.
  static HttpServer? _server;
  static WslTerminalManager? _terminalManager;

  final WSLApi wslApi;
  final McpServerFactory serverFactory;
  final CloudflareTunnelService tunnel;

  WslMcpService({
    WSLApi? wslApi,
    McpServerFactory? serverFactory,
    CloudflareTunnelService? tunnel,
  })  : wslApi = wslApi ?? WSLApi(),
        serverFactory = serverFactory ?? _defaultMcpServerFactory,
        tunnel = tunnel ?? CloudflareTunnelService();

  bool get isRunning => _server != null;

  WslTerminalManager? get terminalManager => _terminalManager;

  bool get enabled => prefs.getBool('McpServerEnabled') ?? false;

  /// The token clients must send as `Authorization: Bearer <token>`.
  /// Generated on first use and persisted; [regenerateToken] rotates it.
  String get token {
    final existing = prefs.getString('McpServerToken');
    if (existing != null && existing.isNotEmpty) return existing;
    return regenerateToken();
  }

  String regenerateToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    final newToken = base64Url.encode(bytes).replaceAll('=', '');
    prefs.setString('McpServerToken', newToken);
    return newToken;
  }

  String get endpointUrl => 'http://127.0.0.1:$port$path';

  /// Where Claude Desktop keeps its config dir; tests point this at a temp
  /// directory.
  static String? claudeDesktopConfigDirOverride;

  /// Claude Desktop's config file path, or null when it is not installed.
  String? claudeDesktopConfigPath() {
    final appData = Platform.environment['APPDATA'];
    final dirPath = claudeDesktopConfigDirOverride ??
        (appData == null || appData.isEmpty ? null : '$appData\\Claude');
    if (dirPath == null || !Directory(dirPath).existsSync()) return null;
    return '$dirPath\\claude_desktop_config.json';
  }

  /// One-click Claude Desktop hookup: writes a `wsl-manager` entry into
  /// claude_desktop_config.json, leaving everything else in the file alone.
  ///
  /// Claude Desktop launches stdio servers only, so the entry bridges to
  /// this HTTP endpoint through `npx mcp-remote`. The bearer token travels
  /// through `env` and an `${AUTH_HEADER}` placeholder that mcp-remote
  /// expands itself — Claude Desktop splits argv on spaces, so the header
  /// cannot be one argument.
  Future<String> connectClaudeDesktop() async {
    final configPath = claudeDesktopConfigPath();
    if (configPath == null) throw Exception('claude-desktop-not-found');
    final file = File(configPath);
    Map<String, dynamic> config = <String, dynamic>{};
    if (file.existsSync()) {
      final text = await file.readAsString();
      if (text.trim().isNotEmpty) {
        // An unparseable config is not ours to clobber — let the decode
        // throw and the caller report it instead of overwriting.
        config = json.decode(text) as Map<String, dynamic>;
      }
    }
    final servers = (config['mcpServers'] as Map<String, dynamic>?) ??
        <String, dynamic>{};
    servers['wsl-manager'] = {
      'command': 'npx',
      'args': [
        '-y',
        'mcp-remote',
        endpointUrl,
        '--header',
        r'Authorization:${AUTH_HEADER}',
      ],
      'env': {'AUTH_HEADER': 'Bearer $token'},
    };
    config['mcpServers'] = servers;
    await file
        .writeAsString(const JsonEncoder.withIndent('  ').convert(config));
    return configPath;
  }

  Future<void> setEnabled(bool value) async {
    prefs.setBool('McpServerEnabled', value);
    if (value) {
      await start();
    } else {
      await stop();
    }
  }

  Future<void> start() async {
    if (isRunning) return;

    _terminalManager = WslTerminalManager(wslApi: wslApi);
    final mcp = McpServer(
      serverName: 'wsl2-distro-manager',
      serverVersion: currentVersion,
      tools: buildWslMcpTools(wslApi, _terminalManager!),
    );

    final handler = const Pipeline()
        .addMiddleware(_authMiddleware(() => token))
        .addHandler((request) => _handleMcpRequest(request, mcp));

    try {
      // 127.0.0.1, not 0.0.0.0: this endpoint can run arbitrary commands in
      // the user's WSL distros and must never be reachable from the LAN.
      _server = await serverFactory(handler, '127.0.0.1', port);
    } catch (_) {
      // Port already in use or otherwise unavailable — leave disabled
      // rather than surfacing a raw exception to the caller.
      _server = null;
    }
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    // Disabling the server shouldn't leave orphaned WSL shell processes
    // running in the background.
    await _terminalManager?.closeAll();
    _terminalManager = null;
    // Nor a public URL still routing to a server that's no longer there.
    await tunnel.stop();
  }

  Future<Response> _handleMcpRequest(Request request, McpServer mcp) async {
    if (request.method != 'POST') {
      return Response(405, body: 'Method not allowed');
    }

    final Map<String, dynamic> message;
    try {
      final body = await request.readAsString();
      message = json.decode(body) as Map<String, dynamic>;
    } catch (_) {
      return Response(400, body: 'Invalid JSON-RPC message');
    }

    final response = await mcp.handle(message);
    if (response == null) {
      // Notification — no reply expected.
      return Response(202);
    }
    return Response.ok(
      json.encode(response),
      headers: {'content-type': 'application/json'},
    );
  }

  Middleware _authMiddleware(String Function() expectedToken) {
    return (Handler innerHandler) {
      return (Request request) {
        final header = request.headers['authorization'] ?? '';
        final expected = 'Bearer ${expectedToken()}';
        if (header != expected) {
          return Response.forbidden(
            json.encode({
              'jsonrpc': '2.0',
              'error': {'code': -32001, 'message': 'Unauthorized'},
            }),
            headers: {'content-type': 'application/json'},
          );
        }
        return innerHandler(request);
      };
    };
  }
}
