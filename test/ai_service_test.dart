import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wsl2distromanager/api/ai_service.dart';
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
}
