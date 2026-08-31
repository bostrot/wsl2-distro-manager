import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wsl2distromanager/api/claude_auth.dart';
import 'package:wsl2distromanager/components/helpers.dart';

/// Same shape as the ai_service_test adapter: record the request, reply from
/// a closure, never touch the network.
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

ResponseBody _tokenJson() => ResponseBody.fromString(
      json.encode({
        'access_token': 'at-fresh',
        'refresh_token': 'rt-fresh',
        'expires_in': 3600,
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

/// Plays the browser: reads the redirect URI out of the authorize URL and
/// bounces straight back to the loopback server. A raw socket, not
/// HttpClient — the flutter_test binding swaps HttpClient for a fake that
/// never touches the network, loopback included.
Future<bool> Function(Uri) _browser(
    {String? code, String Function(String actual)? state}) {
  return (uri) async {
    final redirect = Uri.parse(uri.queryParameters['redirect_uri']!);
    final actualState = uri.queryParameters['state']!;
    final q = <String, String>{
      if (code != null) 'code': code,
      'state': state == null ? actualState : state(actualState),
    };
    final target = redirect.replace(queryParameters: q);
    unawaited(() async {
      final socket = await Socket.connect(target.host, target.port);
      socket.write('GET ${target.path}?${target.query} HTTP/1.1\r\n'
          'Host: ${target.host}\r\n'
          'Connection: close\r\n\r\n');
      await socket.flush();
      // Read the reply to completion so the server sees a clean close.
      await socket.drain<void>();
      socket.destroy();
    }());
    return true;
  };
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    ClaudeAuth().launchAuthUrl =
        (_) async => fail('no browser launch expected');
  });

  group('ClaudeAuth PKCE', () {
    test('matches the RFC 7636 appendix B vector', () {
      expect(
        ClaudeAuth.codeChallengeFor(
            'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'),
        'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
      );
    });
  });

  group('ClaudeAuth sign-in', () {
    test('refuses to start without a client ID', () async {
      expect(ClaudeAuth().hasClientId, false);
      await expectLater(
        ClaudeAuth().signIn(),
        throwsA(predicate(
            (e) => e.toString().contains('claude-clientid-missing'))),
      );
    });

    test('the browser round-trip stores tokens', () async {
      final auth = ClaudeAuth();
      auth.setClientId('client-123');
      final adapter = _RecordingAdapter((options) {
        expect(options.path, ClaudeAuth.tokenEndpoint);
        final body =
            json.decode(options.data as String) as Map<String, dynamic>;
        expect(body['grant_type'], 'authorization_code');
        expect(body['code'], 'auth-code');
        expect(body['client_id'], 'client-123');
        expect(body['code_verifier'], isNotEmpty);
        return _tokenJson();
      });
      auth.dioForTesting = Dio()..httpClientAdapter = adapter;
      auth.launchAuthUrl = (uri) {
        expect(uri.queryParameters['code_challenge_method'], 'S256');
        expect(uri.queryParameters['code_challenge'], isNotEmpty);
        return _browser(code: 'auth-code')(uri);
      };

      await auth.signIn();

      expect(auth.isSignedIn, true);
      expect(prefs.getString('ClaudeAccessToken'), 'at-fresh');
      expect(prefs.getString('ClaudeRefreshToken'), 'rt-fresh');
      expect(adapter.requests, hasLength(1));
    });

    test('a mismatched state is refused', () async {
      final auth = ClaudeAuth();
      auth.setClientId('client-123');
      final adapter =
          _RecordingAdapter((_) => fail('no token exchange expected'));
      auth.dioForTesting = Dio()..httpClientAdapter = adapter;
      auth.launchAuthUrl =
          _browser(code: 'auth-code', state: (_) => 'forged');

      await expectLater(
        auth.signIn(),
        throwsA(predicate(
            (e) => e.toString().contains('claude-signin-failed'))),
      );
      expect(auth.isSignedIn, false);
      expect(adapter.requests, isEmpty);
    });
  });

  group('ClaudeAuth tokens', () {
    void storedTokens({required Duration expiresIn}) {
      prefs.setString('ClaudeAccessToken', 'at-stored');
      prefs.setString('ClaudeRefreshToken', 'rt-stored');
      prefs.setInt('ClaudeTokenExpiry',
          DateTime.now().add(expiresIn).millisecondsSinceEpoch);
    }

    test('a fresh token is reused without a request', () async {
      final auth = ClaudeAuth();
      auth.setClientId('client-123');
      storedTokens(expiresIn: const Duration(hours: 1));
      auth.dioForTesting = Dio()
        ..httpClientAdapter =
            _RecordingAdapter((_) => fail('no request expected'));

      expect(await auth.validAccessToken(), 'at-stored');
    });

    test('an expired token is refreshed through the refresh grant', () async {
      final auth = ClaudeAuth();
      auth.setClientId('client-123');
      storedTokens(expiresIn: const Duration(seconds: -10));
      final adapter = _RecordingAdapter((options) {
        final body =
            json.decode(options.data as String) as Map<String, dynamic>;
        expect(body['grant_type'], 'refresh_token');
        expect(body['refresh_token'], 'rt-stored');
        return _tokenJson();
      });
      auth.dioForTesting = Dio()..httpClientAdapter = adapter;

      expect(await auth.validAccessToken(), 'at-fresh');
      expect(prefs.getString('ClaudeRefreshToken'), 'rt-fresh');
    });

    test('a rejected refresh token signs the account out', () async {
      final auth = ClaudeAuth();
      auth.setClientId('client-123');
      storedTokens(expiresIn: const Duration(seconds: -10));
      auth.dioForTesting = Dio()
        ..httpClientAdapter = _RecordingAdapter(
            (_) => ResponseBody.fromString('{"error":"invalid_grant"}', 400));

      await expectLater(
        auth.validAccessToken(),
        throwsA(predicate(
            (e) => e.toString().contains('claude-signin-required'))),
      );
      expect(auth.isSignedIn, false);
    });

    test('signOut drops all stored tokens', () {
      storedTokens(expiresIn: const Duration(hours: 1));
      expect(ClaudeAuth().isSignedIn, true);
      ClaudeAuth().signOut();
      expect(ClaudeAuth().isSignedIn, false);
      expect(prefs.getString('ClaudeAccessToken'), isNull);
    });
  });
}
