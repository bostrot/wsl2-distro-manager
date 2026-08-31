import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wsl2distromanager/api/ai_service.dart';
import 'package:wsl2distromanager/api/mcp/mcp_server.dart';
import 'package:wsl2distromanager/api/license_manager.dart';
import 'package:wsl2distromanager/components/helpers.dart';

/// Records every request it sees and replies based on the path, so tests can
/// assert both "which endpoint got hit" and "what happened with the reply"
/// without making a real network call.
class _RecordingAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  ResponseBody Function(RequestOptions options) responder;

  _RecordingAdapter(this.responder);

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
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    // Not Pro by default; tests that need it flip the override and re-init.
    LicenseManager.storeInstallCheckOverride = () => false;
    await LicenseManager().init();
  });

  tearDown(() {
    LicenseManager.storeInstallCheckOverride = null;
  });

  group('AiService BYOK configuration', () {
    test('not configured without a key', () {
      final ai = AiService();
      expect(ai.hasByokConfigured, false);
    });

    test('a stored key means configured, independent of Pro status', () {
      final ai = AiService();
      ai.setByokApiKey('sk-test');

      // Configuration is a pure "is the key there" signal — Pro gating
      // happens in sendMessage, not here, so Settings can manage the key
      // regardless of entitlement.
      expect(ai.hasByokConfigured, true);
    });

    test('base URL and model fall back to defaults when unset', () {
      final ai = AiService();
      expect(ai.byokBaseUrl, AiService.defaultByokBaseUrl);
      expect(ai.byokModel, AiService.defaultByokModel);
    });

    test('base URL, key, and model are trimmed and persisted', () {
      final ai = AiService();
      ai.setByokBaseUrl('  https://my-proxy.example.com/v1  ');
      ai.setByokApiKey('  sk-abc123  ');
      ai.setByokModel('  gpt-4o  ');

      expect(ai.byokBaseUrl, 'https://my-proxy.example.com/v1');
      expect(ai.byokApiKey, 'sk-abc123');
      expect(ai.byokModel, 'gpt-4o');
    });

    test('setting an empty value clears the stored override', () {
      final ai = AiService();
      ai.setByokBaseUrl('https://my-proxy.example.com/v1');
      ai.setByokBaseUrl('');

      expect(ai.byokBaseUrl, AiService.defaultByokBaseUrl);
    });
  });

  group('AiService sendMessage', () {
    test('throws pro-required when not Pro', () async {
      final ai = AiService();
      await ai.init();

      expect(
        () => ai.sendMessage('hello'),
        throwsA(predicate((e) => e.toString().contains('pro-required'))),
      );
    });

    test('throws byok-required when Pro but no key is configured', () async {
      final ai = AiService();
      LicenseManager.storeInstallCheckOverride = () => true;
      await LicenseManager().init();
      await ai.init();

      expect(
        () => ai.sendMessage('hello'),
        throwsA(predicate((e) => e.toString().contains('byok-required'))),
      );
    });

    test('sends via the configured endpoint with the bearer key', () async {
      final ai = AiService();
      LicenseManager.storeInstallCheckOverride = () => true;
      await LicenseManager().init();
      ai.setByokApiKey('sk-test');
      ai.setByokBaseUrl('https://my-proxy.example.com/v1');
      ai.setByokModel('gpt-4o');
      await ai.init();
      ai.clearHistory();

      final adapter = _RecordingAdapter((options) {
        expect(options.headers['Authorization'], 'Bearer sk-test');
        return ResponseBody.fromString(
          json.encode({
            'choices': [
              {
                'message': {'content': 'byok reply'}
              }
            ]
          }),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });
      ai.dioForTesting.httpClientAdapter = adapter;

      final reply = await ai.sendMessage('hello');

      expect(reply, 'byok reply');
      expect(adapter.requests, hasLength(1));
      expect(adapter.requests.single.path,
          'https://my-proxy.example.com/v1/chat/completions');
      final body = json.decode(adapter.requests.single.data as String)
          as Map<String, dynamic>;
      expect(body['model'], 'gpt-4o');
    });

    test('a request failure removes the pending user message from history',
        () async {
      final ai = AiService();
      LicenseManager.storeInstallCheckOverride = () => true;
      await LicenseManager().init();
      ai.setByokApiKey('sk-test');
      await ai.init();
      ai.clearHistory();

      final adapter = _RecordingAdapter((options) {
        return ResponseBody.fromString('server error', 500);
      });
      ai.dioForTesting.httpClientAdapter = adapter;

      await expectLater(ai.sendMessage('hello'), throwsException);
      expect(ai.conversationHistory, isEmpty);
    });
  });

  group('AiService Claude provider', () {
    test('defaults to the BYOK path and switches per preference', () {
      final ai = AiService();
      expect(ai.aiProvider, 'openai');
      expect(ai.usesClaudeAccount, false);

      ai.setAiProvider('claude');
      expect(ai.usesClaudeAccount, true);
      // Not signed in, so the provider is unconfigured — and the message the
      // UI would show talks about signing in, not about API keys.
      expect(ai.hasAiConfigured, false);
      expect(ai.configRequiredKey, 'claude-signin-required-text');

      ai.setAiProvider('openai');
      expect(ai.configRequiredKey, 'byok-required-text');
    });

    test('throws claude-signin-required when Pro but not signed in', () async {
      final ai = AiService();
      LicenseManager.storeInstallCheckOverride = () => true;
      await LicenseManager().init();
      ai.setAiProvider('claude');
      await ai.init();

      await expectLater(
        ai.sendMessage('hello'),
        throwsA(predicate(
            (e) => e.toString().contains('claude-signin-required'))),
      );
    });

    test('sends to the Messages API with the OAuth bearer', () async {
      final ai = AiService();
      LicenseManager.storeInstallCheckOverride = () => true;
      await LicenseManager().init();
      ai.setAiProvider('claude');
      prefs.setString('ClaudeRefreshToken', 'rt-1');
      prefs.setString('ClaudeAccessToken', 'at-1');
      prefs.setInt(
          'ClaudeTokenExpiry',
          DateTime.now()
              .add(const Duration(hours: 1))
              .millisecondsSinceEpoch);
      await ai.init();
      ai.clearHistory();

      final adapter = _RecordingAdapter((options) {
        expect(options.headers['Authorization'], 'Bearer at-1');
        expect(options.headers['anthropic-beta'], 'oauth-2025-04-20');
        expect(options.headers['anthropic-version'], isNotNull);
        return ResponseBody.fromString(
          json.encode({
            'content': [
              {'type': 'text', 'text': 'claude reply'}
            ]
          }),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });
      ai.dioForTesting.httpClientAdapter = adapter;

      final reply = await ai.sendMessage('hello');

      expect(reply, 'claude reply');
      expect(adapter.requests, hasLength(1));
      expect(adapter.requests.single.path, AiService.claudeMessagesEndpoint);
      final body = json.decode(adapter.requests.single.data as String)
          as Map<String, dynamic>;
      expect(body['model'], AiService.defaultClaudeModel);
      expect(body['max_tokens'], isA<int>());
    });
  });

  group('AiService model list and test probe', () {
    test('lists BYOK models from /models with the typed key', () async {
      final ai = AiService();
      final adapter = _RecordingAdapter((options) {
        expect(options.path, 'https://typed.example.com/v1/models');
        expect(options.headers['Authorization'], 'Bearer typed-key');
        return ResponseBody.fromString(
          json.encode({
            'data': [
              {'id': 'b-model'},
              {'id': 'a-model'}
            ]
          }),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });
      ai.dioForTesting.httpClientAdapter = adapter;

      final models = await ai.listModels(
          baseUrl: 'https://typed.example.com/v1', apiKey: 'typed-key');

      expect(models, ['a-model', 'b-model']);
    });

    test('lists Claude models with the OAuth bearer', () async {
      final ai = AiService();
      prefs.setString('ClaudeRefreshToken', 'rt-1');
      prefs.setString('ClaudeAccessToken', 'at-1');
      prefs.setInt(
          'ClaudeTokenExpiry',
          DateTime.now()
              .add(const Duration(hours: 1))
              .millisecondsSinceEpoch);
      final adapter = _RecordingAdapter((options) {
        expect(options.path, 'https://api.anthropic.com/v1/models');
        expect(options.headers['Authorization'], 'Bearer at-1');
        return ResponseBody.fromString(
          json.encode({
            'data': [
              {'id': 'claude-x'}
            ]
          }),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });
      ai.dioForTesting.httpClientAdapter = adapter;

      expect(await ai.listModels(provider: 'claude'), ['claude-x']);
    });

    test('the test probe posts one tiny chat request as typed', () async {
      final ai = AiService();
      final adapter = _RecordingAdapter((options) {
        final body =
            json.decode(options.data as String) as Map<String, dynamic>;
        expect(body['model'], 'typed-model');
        expect(body['max_tokens'], 16);
        return ResponseBody.fromString(json.encode({'choices': []}), 200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            });
      });
      ai.dioForTesting.httpClientAdapter = adapter;

      await ai.testConnection(
          baseUrl: 'https://typed.example.com/v1',
          apiKey: 'k',
          model: 'typed-model');

      expect(adapter.requests.single.path,
          'https://typed.example.com/v1/chat/completions');
    });

    test('a refused probe throws ai-test-failed', () async {
      final ai = AiService();
      ai.dioForTesting.httpClientAdapter =
          _RecordingAdapter((_) => ResponseBody.fromString('denied', 401));

      await expectLater(
        ai.testConnection(
            baseUrl: 'https://x.example.com/v1', apiKey: 'k', model: 'm'),
        throwsA(predicate((e) => e.toString().contains('ai-test-failed'))),
      );
    });
  });

  group('AiService tool-use agent', () {
    late McpTool echoTool;
    late List<Map<String, dynamic>> echoArgs;

    setUp(() {
      echoArgs = [];
      echoTool = McpTool(
        name: 'echo',
        description: 'echoes text',
        inputSchema: const {
          'type': 'object',
          'properties': {
            'text': {'type': 'string'}
          },
          'required': ['text'],
        },
        handler: (args) async {
          echoArgs.add(args);
          return 'echoed:${args['text']}';
        },
      );
    });

    ResponseBody _json(Map<String, dynamic> body) => ResponseBody.fromString(
          json.encode(body),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );

    test('BYOK: a tool call runs, its result is fed back, answer returns',
        () async {
      final ai = AiService();
      LicenseManager.storeInstallCheckOverride = () => true;
      await LicenseManager().init();
      ai.setByokApiKey('sk-test');
      ai.toolsForTesting = [echoTool];
      await ai.init();
      ai.clearHistory();

      var call = 0;
      final adapter = _RecordingAdapter((options) {
        call++;
        if (call == 1) {
          // First turn: ask to call the tool.
          return _json({
            'choices': [
              {
                'message': {
                  'role': 'assistant',
                  'content': null,
                  'tool_calls': [
                    {
                      'id': 'c1',
                      'type': 'function',
                      'function': {
                        'name': 'echo',
                        'arguments': '{"text":"hi"}',
                      },
                    }
                  ],
                }
              }
            ]
          });
        }
        // Second turn: the tool result must be present, then answer.
        final body = json.decode(options.data as String) as Map<String, dynamic>;
        final msgs = body['messages'] as List;
        expect(
            msgs.any((m) => m['role'] == 'tool' && m['content'] == 'echoed:hi'),
            true);
        return _json({
          'choices': [
            {
              'message': {'role': 'assistant', 'content': 'done: hi'}
            }
          ]
        });
      });
      ai.dioForTesting.httpClientAdapter = adapter;

      var updates = 0;
      final reply = await ai.sendMessage('echo hi', onUpdate: () => updates++);

      expect(reply, 'done: hi');
      expect(echoArgs.single['text'], 'hi');
      expect(adapter.requests, hasLength(2));
      expect(updates, greaterThan(0));
      // The transcript carries a tool note.
      expect(ai.conversationHistory.any((m) => m.role == 'tool'), true);
    });

    test('Claude: tool_use loop feeds tool_result back and answers', () async {
      final ai = AiService();
      LicenseManager.storeInstallCheckOverride = () => true;
      await LicenseManager().init();
      ai.setAiProvider('claude');
      prefs.setString('ClaudeRefreshToken', 'rt-1');
      prefs.setString('ClaudeAccessToken', 'at-1');
      prefs.setInt(
          'ClaudeTokenExpiry',
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch);
      ai.toolsForTesting = [echoTool];
      await ai.init();
      ai.clearHistory();

      var call = 0;
      final adapter = _RecordingAdapter((options) {
        call++;
        // Tools must be advertised.
        final body = json.decode(options.data as String) as Map<String, dynamic>;
        expect(body['tools'], isNotNull);
        if (call == 1) {
          return _json({
            'stop_reason': 'tool_use',
            'content': [
              {'type': 'text', 'text': 'checking'},
              {
                'type': 'tool_use',
                'id': 't1',
                'name': 'echo',
                'input': {'text': 'hi'},
              }
            ]
          });
        }
        // The tool_result block must be in the follow-up.
        final msgs = body['messages'] as List;
        final hasResult = msgs.any((m) =>
            m['content'] is List &&
            (m['content'] as List)
                .any((b) => b is Map && b['type'] == 'tool_result'));
        expect(hasResult, true);
        return _json({
          'stop_reason': 'end_turn',
          'content': [
            {'type': 'text', 'text': 'all done'}
          ]
        });
      });
      ai.dioForTesting.httpClientAdapter = adapter;

      final reply = await ai.sendMessage('echo hi');

      expect(reply, 'all done');
      expect(echoArgs.single['text'], 'hi');
      expect(adapter.requests, hasLength(2));
    });

    test('with no tools it still answers in one turn', () async {
      final ai = AiService();
      LicenseManager.storeInstallCheckOverride = () => true;
      await LicenseManager().init();
      ai.setByokApiKey('sk-test');
      ai.toolsForTesting = [];
      await ai.init();
      ai.clearHistory();

      ai.dioForTesting.httpClientAdapter = _RecordingAdapter((_) => _json({
            'choices': [
              {
                'message': {'role': 'assistant', 'content': 'plain answer'}
              }
            ]
          }));

      expect(await ai.sendMessage('hi'), 'plain answer');
    });
  });
}
