import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart';
import 'package:wsl2distromanager/api/mcp/cloudflare_tunnel_service.dart';
import 'package:wsl2distromanager/api/vm/vm_backend.dart';
import 'package:wsl2distromanager/api/web/web_dashboard_service.dart';
import 'package:wsl2distromanager/components/helpers.dart';

import 'mocks.dart';

/// A backend that records what the dashboard asked of it, without any
/// wsl.exe or vmctl behind it.
class _FakeBackend extends VmBackend {
  List<String> all = ['Ubuntu', 'Debian'];
  List<String> running = ['Ubuntu'];
  final List<String> calls = [];
  bool failList = false;

  @override
  String get backendId => 'fake';

  @override
  String get instanceNoun => 'distro';

  @override
  VmFeatures get features => const VmFeatures(quickActions: true);

  @override
  Future<Instances> list(bool showDocker) async {
    calls.add('list');
    if (failList) throw Exception('backend down');
    lastDistroList = Instances(List.of(all), List.of(running));
    return lastDistroList;
  }

  @override
  Future<List<String>> listRunning() async => List.of(running);

  @override
  Future<void> start(String distribution,
      {String startPath = '', String startUser = '', String startCmd = ''}) async {
    calls.add('start $distribution');
  }

  @override
  Future<String> stop(String distribution) async {
    calls.add('stop $distribution');
    running.remove(distribution);
    return '';
  }

  @override
  Future<String> shutdown() async {
    calls.add('shutdown');
    running.clear();
    return '';
  }

  @override
  Future<String> remove(String distribution) async {
    calls.add('remove $distribution');
    all.remove(distribution);
    return '';
  }

  @override
  Future<String> export(String distribution, String location,
          {String? format}) async =>
      '';

  @override
  Future<String> import(
          String distribution, String installLocation, String filename,
          {bool isVhd = false}) async =>
      '';

  @override
  Future<String> execCmdAsRoot(String distribution, String cmd) async {
    calls.add('exec $distribution $cmd');
    if (!running.contains(distribution)) running.add(distribution);
    return 'ran: $cmd';
  }

  @override
  Future<Process> startShell(String distribution, {String? user}) =>
      throw UnimplementedError();

  @override
  Future<String?> getSize(String distribution) async => '1 GB';

  @override
  String currentDistroPath(String distribution) => '/vms/$distribution';

  @override
  Future<String> getDefaultUser(String distribution) async => 'root';

  @override
  Future<void> runCommands(String instance, List<String> commands,
      {String? user}) async {}

  @override
  Future<String> copy(String distribution, String newName) async {
    calls.add('copy $distribution $newName');
    all.add(newName);
    return '';
  }

  @override
  void startExplorer(String distribution) {}

  @override
  String instanceSizeLabel(String distribution) => '1 GB';
}

class _FakeInterface implements NetworkInterface {
  @override
  final String name;
  @override
  final List<InternetAddress> addresses;
  @override
  final int index = 0;

  _FakeInterface(this.name, List<String> ips)
      : addresses = [for (final ip in ips) InternetAddress(ip)];
}

void main() {
  late _FakeBackend backend;
  late MockHttpServer mockServer;
  Handler? capturedHandler;
  Object? boundAddress;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    backend = _FakeBackend();
    mockServer = MockHttpServer();
    capturedHandler = null;
    boundAddress = null;
  });

  tearDown(() async {
    // The server handle is static (see web_dashboard_service.dart), so a
    // server left "running" by one test would make the next test's start()
    // skip its own factory and leave capturedHandler null.
    await WebDashboardService().stop();
  });

  WebDashboardService service({
    NetworkInterfaceLister? interfaces,
    CloudflareTunnelService? tunnel,
  }) =>
      WebDashboardService(
        backend: backend,
        serverFactory: (handler, address, port) async {
          capturedHandler = handler;
          boundAddress = address;
          return mockServer;
        },
        interfaceLister: interfaces ?? () async => [],
        tunnel: tunnel,
      );

  Future<Response> call(
    String path, {
    String method = 'GET',
    String? token,
    Map<String, String>? headers,
    Object? body,
  }) async {
    final uri = Uri.parse('http://192.168.1.2:${WebDashboardService.port}$path')
        .replace(queryParameters: {
      if (token != null) 'token': token,
    });
    return await capturedHandler!(Request(
      method,
      uri,
      headers: headers,
      body: body == null ? null : json.encode(body),
    ));
  }

  Future<Map<String, dynamic>> decode(Response response) async =>
      json.decode(await response.readAsString()) as Map<String, dynamic>;

  test('start() binds every interface — being reachable is the point',
      () async {
    final svc = service();
    await svc.start();

    expect(boundAddress, '0.0.0.0');
    expect(svc.isRunning, true);
  });

  test('stop() closes the server, clears isRunning and tears the tunnel down',
      () async {
    final tunnel = CloudflareTunnelService(
      localPort: WebDashboardService.port,
      processSpawner: (_, __) async => throw StateError('never spawned'),
      binaryLocatorOverride: () async => 'cloudflared',
    );
    final svc = service(tunnel: tunnel);
    await svc.start();

    await svc.stop();

    expect(mockServer.closed, true);
    expect(svc.isRunning, false);
    expect(tunnel.isRunning, false);
  });

  test('a failed bind rethrows and leaves the preference off', () async {
    final svc = WebDashboardService(
      backend: backend,
      serverFactory: (_, __, ___) async => throw const SocketException('busy'),
      interfaceLister: () async => [],
    );

    await expectLater(svc.setEnabled(true), throwsA(isA<SocketException>()));

    expect(svc.isRunning, false);
    expect(prefs.getBool('WebDashboardEnabled'), false);
  });

  group('token', () {
    test('is generated once and stays stable', () {
      final svc = service();
      expect(svc.token, isNotEmpty);
      expect(svc.token, svc.token);
    });

    test('regenerateToken() rotates it and every link with it', () {
      final svc = service();
      final before = svc.localUrl;
      final rotated = svc.regenerateToken();

      expect(svc.token, rotated);
      expect(svc.localUrl, isNot(before));
      expect(svc.localUrl, contains('token=$rotated'));
    });

    test('links carry the token as a query parameter', () {
      final svc = service();
      final uri = Uri.parse(svc.urlFor('10.0.0.5'));
      expect(uri.host, '10.0.0.5');
      expect(uri.port, WebDashboardService.port);
      expect(uri.queryParameters['token'], svc.token);
    });
  });

  group('auth', () {
    test('rejects the page without a token, revealing nothing', () async {
      final svc = service();
      await svc.start();

      final response = await call('/');

      expect(response.statusCode, 403);
      final html = await response.readAsString();
      expect(html, isNot(contains('api/state')));
      expect(html, isNot(contains(svc.token)));
    });

    test('rejects an API call with the wrong token as JSON', () async {
      final svc = service();
      await svc.start();

      final response = await call('/api/state', token: 'nope');

      expect(response.statusCode, 403);
      expect((await decode(response))['ok'], false);
    });

    test('accepts the token as a query parameter', () async {
      final svc = service();
      await svc.start();

      final response = await call('/', token: svc.token);

      expect(response.statusCode, 200);
      expect(response.headers['content-type'], contains('text/html'));
      expect(await response.readAsString(), contains('/api/state'));
    });

    test('accepts the token in the dashboard header and as a bearer',
        () async {
      final svc = service();
      await svc.start();

      final viaHeader = await call('/api/state',
          headers: {WebDashboardService.tokenHeader: svc.token});
      final viaBearer = await call('/api/state',
          headers: {'authorization': 'Bearer ${svc.token}'});

      expect(viaHeader.statusCode, 200);
      expect(viaBearer.statusCode, 200);
    });
  });

  group('/api/state', () {
    test('lists instances with their state and the backend facts', () async {
      final svc = service();
      await svc.start();

      final body = await decode(await call('/api/state', token: svc.token));

      expect(body['host']['backend'], 'fake');
      expect(body['host']['instanceNoun'], 'distro');
      expect(body['host']['features']['quickActions'], true);
      final instances = (body['instances'] as List).cast<Map>();
      expect(instances.map((i) => i['name']), ['Ubuntu', 'Debian']);
      expect(instances.first['running'], true);
      expect(instances.last['running'], false);
      expect(instances.first['path'], '/vms/Ubuntu');
      expect(body['sessions'], isEmpty);
    });

    test('falls back to the last known list and reports the failure',
        () async {
      final svc = service();
      await svc.start();
      await call('/api/state', token: svc.token);
      backend.failList = true;

      final body = await decode(await call('/api/state', token: svc.token));

      expect(body['error'], contains('backend down'));
      expect((body['instances'] as List).length, 2);
    });
  });

  group('instance actions', () {
    test('start runs a no-op command so no window opens on the host',
        () async {
      final svc = service();
      await svc.start();

      final body = await decode(await call('/api/instances/Debian/start',
          method: 'POST', token: svc.token));

      expect(body['ok'], true);
      expect(backend.calls, contains('exec Debian true'));
      expect(backend.calls, isNot(contains('start Debian')));
    });

    test('stop, copy and shutdown reach the backend', () async {
      final svc = service();
      await svc.start();

      await call('/api/instances/Ubuntu/stop', method: 'POST', token: svc.token);
      final copy = await decode(await call('/api/instances/Ubuntu/copy',
          method: 'POST', token: svc.token, body: {'new_name': 'Ubuntu-2'}));
      await call('/api/shutdown', method: 'POST', token: svc.token);

      expect(copy['ok'], true);
      expect(backend.calls,
          containsAll(['stop Ubuntu', 'copy Ubuntu Ubuntu-2', 'shutdown']));
    });

    test('copy without a new name is a 400, not a backend call', () async {
      final svc = service();
      await svc.start();

      final response = await call('/api/instances/Ubuntu/copy',
          method: 'POST', token: svc.token, body: {'new_name': ' '});

      expect(response.statusCode, 400);
      expect(backend.calls.where((c) => c.startsWith('copy')), isEmpty);
    });

    test('actions are POST only', () async {
      final svc = service();
      await svc.start();

      final response =
          await call('/api/instances/Ubuntu/stop', token: svc.token);

      expect(response.statusCode, 405);
      expect(backend.calls, isNot(contains('stop Ubuntu')));
    });
  });

  group('/api/tools', () {
    test('lists the MCP tool set with schemas', () async {
      final svc = service();
      await svc.start();

      final body = await decode(await call('/api/tools', token: svc.token));

      final tools = (body['tools'] as List).cast<Map>();
      final names = tools.map((t) => t['name']).toSet();
      expect(names, containsAll({'wsl_list_distros', 'wsl_run_command',
          'wsl_unregister_distro', 'wsl_terminal_start'}));
      expect(tools.first['inputSchema'], isA<Map>());
    });

    test('calling a tool round-trips through the backend', () async {
      final svc = service();
      await svc.start();

      final body = await decode(await call('/api/tools/wsl_run_command',
          method: 'POST',
          token: svc.token,
          body: {
            'arguments': {'distro': 'Ubuntu', 'command': 'uname -a'}
          }));

      expect(body['ok'], true);
      expect(body['text'], 'ran: uname -a');
      expect(backend.calls, contains('exec Ubuntu uname -a'));
    });

    test('a tool error comes back as ok:false, never as a 500', () async {
      final svc = service();
      await svc.start();

      final body = await decode(await call('/api/tools/wsl_unregister_distro',
          method: 'POST',
          token: svc.token,
          body: {
            'arguments': {'distro': 'Ubuntu'}
          }));

      expect(body['ok'], false);
      expect(body['error'], contains('confirm'));
      expect(backend.all, contains('Ubuntu'));
    });

    test('an unknown tool is a 404 and malformed JSON a 400', () async {
      final svc = service();
      await svc.start();

      final unknown =
          await call('/api/tools/nope', method: 'POST', token: svc.token);
      final malformed = await capturedHandler!(Request(
        'POST',
        Uri.parse('http://h:1/api/tools/wsl_list_distros?token=${svc.token}'),
        body: '{not json',
      ));

      expect(unknown.statusCode, 404);
      expect(malformed.statusCode, 400);
    });
  });

  group('share links', () {
    test('lanAddresses() drops loopback and link-local and prefers private',
        () async {
      final svc = service(
        interfaces: () async => [
          _FakeInterface('en0', ['203.0.113.7', '10.1.2.3']),
          _FakeInterface('lo0', ['127.0.0.1']),
          _FakeInterface('awdl0', ['169.254.10.10']),
          _FakeInterface('en1', ['192.168.1.20']),
        ],
      );

      expect(await svc.lanAddresses(),
          ['192.168.1.20', '10.1.2.3', '203.0.113.7']);
      final urls = await svc.shareUrls();
      expect(urls.first, svc.urlFor('192.168.1.20'));
      expect(urls, everyElement(contains('token=${svc.token}')));
    });

    test('a failing interface probe yields no LAN links, not an exception',
        () async {
      final svc = service(interfaces: () async => throw Exception('no net'));

      expect(await svc.lanAddresses(), isEmpty);
    });

    test('tunnelUrl is null until the tunnel is up and carries the token',
        () async {
      final svc = service(
        tunnel: CloudflareTunnelService(
          localPort: WebDashboardService.port,
          processSpawner: (_, __) async => throw StateError('never spawned'),
          binaryLocatorOverride: () async => 'cloudflared',
        ),
      );

      expect(svc.tunnelUrl, isNull);
    });
  });

  test('setEnabled persists the preference and starts/stops the server',
      () async {
    final svc = service();

    await svc.setEnabled(true);
    expect(prefs.getBool('WebDashboardEnabled'), true);
    expect(svc.isRunning, true);

    await svc.setEnabled(false);
    expect(prefs.getBool('WebDashboardEnabled'), false);
    expect(svc.isRunning, false);
  });
}
