import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wsl2distromanager/api/ai_service.dart';
import 'package:wsl2distromanager/api/app.dart';
import 'package:wsl2distromanager/api/license_manager.dart';
import 'package:wsl2distromanager/api/mcp/mcp_server.dart';
import 'package:wsl2distromanager/api/mcp/wsl_mcp_tools.dart';
import 'package:wsl2distromanager/api/mcp/wsl_terminal_manager.dart';
import 'package:wsl2distromanager/api/sandbox_service.dart';
import 'package:wsl2distromanager/api/wsl.dart';
import 'package:wsl2distromanager/components/helpers.dart';

import 'mocks.dart';

class _FakeApp extends App {
  _FakeApp(this.links);
  final Map<String, String> links;
  @override
  Future<Map<String, String>> getDistroLinks() async => links;
}

class _StringAdapter implements HttpClientAdapter {
  final ResponseBody Function(RequestOptions) responder;
  final List<RequestOptions> requests = [];
  _StringAdapter(this.responder);
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    return responder(options);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  setUpAll(() => TestWidgetsFlutterBinding.ensureInitialized());

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    LicenseManager.storeInstallCheckOverride = () => false;
    await LicenseManager().init();
  });

  tearDown(() => LicenseManager.storeInstallCheckOverride = null);

  group('SandboxService', () {
    test('tracks sandbox names in prefs', () {
      final svc = SandboxService();
      expect(svc.list(), isEmpty);
      expect(svc.isSandbox('wslm-sandbox-x'), false);
      expect(svc.distroNameFor('My Box!'), 'wslm-sandbox-My_Box_');
    });

    test('createUbuntuSandbox picks Ubuntu, downloads, imports, records',
        () async {
      final shell = MockShell();
      final api = WSLApi(shell: shell);
      final dio = Dio()
        ..httpClientAdapter = _StringAdapter(
            (_) => ResponseBody.fromString('rootfs-bytes', 200));
      final svc = SandboxService(
        api: api,
        app: _FakeApp({
          'Alpine': 'https://example.com/alpine.tar.gz',
          'Ubuntu-24.04': 'https://example.com/ubuntu-2404.tar.gz',
          'Ubuntu-22.04': 'https://example.com/ubuntu-2204.tar.gz',
        }),
        dio: dio,
      );

      final distro = await svc.createUbuntuSandbox('play');

      expect(distro, 'wslm-sandbox-play');
      expect(svc.list(), contains('wslm-sandbox-play'));
      expect(svc.isSandbox('wslm-sandbox-play'), true);
      // Imported via wsl --import, not some other distro's rootfs.
      expect(shell.runCalls.any((c) => c.contains('--import')), true);
    });

    test('refuses a blank name', () async {
      await expectLater(
          SandboxService(api: WSLApi(shell: MockShell()))
              .createUbuntuSandbox('   '),
          throwsArgumentError);
    });

    test('a named catalog image overrides the Ubuntu default', () async {
      final adapter = _StringAdapter(
          (_) => ResponseBody.fromString('rootfs-bytes', 200));
      final svc = SandboxService(
        api: WSLApi(shell: MockShell()),
        app: _FakeApp({
          'Alpine': 'https://example.com/alpine.tar.gz',
          'Ubuntu-24.04': 'https://example.com/ubuntu-2404.tar.gz',
        }),
        dio: Dio()..httpClientAdapter = adapter,
      );

      await svc.createUbuntuSandbox('alp', image: 'Alpine');

      expect(adapter.requests.single.path,
          'https://example.com/alpine.tar.gz');
    });

    test('creation publishes stage and clears it when done', () async {
      final svc = SandboxService(
        api: WSLApi(shell: MockShell()),
        app: _FakeApp({'Ubuntu-24.04': 'https://example.com/u.tar.gz'}),
        dio: Dio()
          ..httpClientAdapter = _StringAdapter(
              (_) => ResponseBody.fromString('rootfs-bytes', 200)),
      );
      final stages = <String?>[];
      void listener() => stages.add(SandboxService.creationStage.value);
      SandboxService.creationStage.addListener(listener);
      addTearDown(
          () => SandboxService.creationStage.removeListener(listener));

      await svc.createUbuntuSandbox('stagey');

      expect(stages, containsAllInOrder(['resolving', 'downloading', 'importing', null]));
      expect(SandboxService.isCreating, false);
    });
  });

  group('buildSandboxTools scoping', () {
    late MockShell shell;
    late WSLApi api;
    late WslTerminalManager tm;

    setUp(() {
      shell = MockShell();
      api = WSLApi(shell: shell);
      tm = WslTerminalManager(wslApi: api);
    });

    McpTool tool(String name) =>
        buildSandboxTools(api, tm, 'wslm-sandbox-box')
            .firstWhere((t) => t.name == name);

    test('only sandbox_* tools, no lifecycle or other-distro access', () {
      final names = buildSandboxTools(api, tm, 'wslm-sandbox-box')
          .map((t) => t.name)
          .toSet();
      expect(names, {
        'sandbox_run_command',
        'sandbox_write_file',
        'sandbox_read_file',
        'sandbox_terminal_start',
        'sandbox_terminal_send',
        'sandbox_terminal_read',
        'sandbox_terminal_close',
      });
      // No way to name another distro, unregister, or reach the host.
      expect(names.any((n) => n.contains('unregister')), false);
      expect(names.any((n) => n.contains('list_distros')), false);
    });

    test('run_command is hardcoded to the sandbox distro', () async {
      await tool('sandbox_run_command').handler({'command': 'whoami'});
      // The -d flag names the sandbox, and only the sandbox — the command has
      // no distro argument to override it.
      final call = shell.runCalls.last;
      final dIndex = call.indexOf('-d');
      expect(dIndex, isNonNegative);
      expect(call[dIndex + 1], 'wslm-sandbox-box');
    });
  });

  group('SandboxChat', () {
    test('runs the agent with the sandbox tools and returns the answer',
        () async {
      LicenseManager.storeInstallCheckOverride = () => true;
      await LicenseManager().init();
      final ai = AiService();
      ai.setByokApiKey('sk-test');
      ai.setAiProvider('openai');

      final chat = SandboxChat.forTesting('wslm-sandbox-box', service: ai);
      // A trivial tool so the loop has something scoped to offer, though the
      // model answers directly here.
      chat.toolsForTesting = [
        McpTool(
          name: 'sandbox_noop',
          description: 'noop',
          inputSchema: const {'type': 'object', 'properties': {}},
          handler: (_) async => 'ok',
        )
      ];

      ai.dioForTesting.httpClientAdapter = _StringAdapter((_) =>
          ResponseBody.fromString(
            json.encode({
              'choices': [
                {
                  'message': {'role': 'assistant', 'content': 'inside sandbox'}
                }
              ]
            }),
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType]
            },
          ));

      final reply = await chat.send('hi');
      expect(reply, 'inside sandbox');
      expect(chat.history.where((m) => m.role == 'user'), hasLength(1));
      expect(chat.history.where((m) => m.role == 'assistant'), hasLength(1));
    });

    test('throws pro-required when not Pro', () async {
      final chat = SandboxChat.forTesting('wslm-sandbox-box');
      await expectLater(chat.send('hi'),
          throwsA(predicate((e) => e.toString().contains('pro-required'))));
    });

    test('history persists across close and reopen', () {
      // The user-visible guarantee: closing the panel and reopening the chat
      // comes back to the same conversation, not an empty one.
      prefs.setStringList('SandboxDistros', ['wslm-sandbox-persist']);
      prefs.setString(
          'SandboxChat_wslm-sandbox-persist',
          json.encode([
            AiMessage(
                    role: 'user',
                    content: 'remember me',
                    timestamp: DateTime.now())
                .toJson()
          ]));

      final chat = SandboxChat.of('wslm-sandbox-persist');
      expect(chat.history.single.content, 'remember me');
      // It shows up in the "last sessions" list…
      expect(SandboxChat.sessions(), contains('wslm-sandbox-persist'));
      // …and the same instance comes back on reopen.
      expect(identical(chat, SandboxChat.of('wslm-sandbox-persist')), true);

      SandboxChat.dropTranscript('wslm-sandbox-persist');
      expect(prefs.getString('SandboxChat_wslm-sandbox-persist'), isNull);
    });
  });
}
