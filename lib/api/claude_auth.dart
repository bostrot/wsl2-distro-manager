// Sign in with Claude: OAuth 2.0 + PKCE against the user's own Claude
// subscription, as the alternative to pasting an API key. The app never sees
// a password — the browser does the sign-in, a one-shot loopback server
// catches the redirect, and only the resulting tokens are stored.
//
// Requires an OAuth client ID from Anthropic's "Sign in with Claude" program
// (registered in the Anthropic Console). Without one the flow is disabled in
// Settings; piggybacking on another product's client ID is against
// Anthropic's terms, so none is bundled.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wsl2distromanager/components/helpers.dart';

class ClaudeAuth {
  static final ClaudeAuth _instance = ClaudeAuth._internal();
  factory ClaudeAuth() => _instance;
  ClaudeAuth._internal();

  static const String authorizeEndpoint = 'https://claude.ai/oauth/authorize';
  static const String tokenEndpoint =
      'https://console.anthropic.com/v1/oauth/token';
  static const String scopes = 'user:profile user:inference';

  Dio _dio = Dio();

  @visibleForTesting
  set dioForTesting(Dio dio) => _dio = dio;

  /// How the browser hand-off is launched; injectable so tests can catch the
  /// URL instead of opening a real browser.
  @visibleForTesting
  Future<bool> Function(Uri) launchAuthUrl = (uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  /// The registered "Sign in with Claude" client ID. A build can bake one in
  /// with --dart-define=WSLM_CLAUDE_CLIENT_ID=...; the Settings field
  /// overrides it.
  String get clientId {
    final stored = prefs.getString('ClaudeOAuthClientId')?.trim();
    if (stored != null && stored.isNotEmpty) return stored;
    return const String.fromEnvironment('WSLM_CLAUDE_CLIENT_ID');
  }

  void setClientId(String id) {
    final trimmed = id.trim();
    if (trimmed.isEmpty) {
      prefs.remove('ClaudeOAuthClientId');
    } else {
      prefs.setString('ClaudeOAuthClientId', trimmed);
    }
  }

  bool get hasClientId => clientId.isNotEmpty;

  bool get isSignedIn =>
      (prefs.getString('ClaudeRefreshToken') ?? '').isNotEmpty;

  /// RFC 7636: challenge = BASE64URL(SHA256(ASCII(verifier))), unpadded.
  @visibleForTesting
  static String codeChallengeFor(String verifier) =>
      base64UrlEncode(sha256.convert(ascii.encode(verifier)).bytes)
          .replaceAll('=', '');

  static String _randomUrlSafe(int bytes) {
    final rng = Random.secure();
    return base64UrlEncode(
            List<int>.generate(bytes, (_) => rng.nextInt(256)))
        .replaceAll('=', '');
  }

  /// Runs the whole browser sign-in: throws on refusal, timeout (3 minutes)
  /// or a failed token exchange; returns normally once tokens are stored.
  Future<void> signIn() async {
    if (!hasClientId) throw Exception('claude-clientid-missing');

    final verifier = _randomUrlSafe(64);
    final state = _randomUrlSafe(32);

    // Port 0: the OS picks a free one, so nothing clashes with the sync or
    // dashboard servers the app may also be running.
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirectUri = 'http://localhost:${server.port}/callback';

    String? code;
    try {
      final url = Uri.parse(authorizeEndpoint).replace(queryParameters: {
        'response_type': 'code',
        'client_id': clientId,
        'redirect_uri': redirectUri,
        'scope': scopes,
        'state': state,
        'code_challenge': codeChallengeFor(verifier),
        'code_challenge_method': 'S256',
      });
      if (!await launchAuthUrl(url)) throw Exception('claude-signin-failed');

      // Browsers poke for favicons and the like; only /callback with an
      // outcome ends the wait.
      await for (final req
          in server.timeout(const Duration(minutes: 3))) {
        final q = req.uri.queryParameters;
        if (req.uri.path != '/callback' ||
            (!q.containsKey('code') && !q.containsKey('error'))) {
          req.response.statusCode = HttpStatus.notFound;
          await req.response.close();
          continue;
        }
        final ok = q['state'] == state && q.containsKey('code');
        req.response.headers.contentType = ContentType.html;
        req.response.write(ok
            ? '<html><body style="font-family:sans-serif"><h3>Signed in.'
                '</h3><p>You can close this tab and return to WSL Manager.'
                '</p></body></html>'
            : '<html><body style="font-family:sans-serif"><h3>Sign-in did '
                'not complete.</h3><p>Return to WSL Manager and try again.'
                '</p></body></html>');
        await req.response.close();
        if (!ok) throw Exception('claude-signin-failed');
        code = q['code'];
        break;
      }
    } on TimeoutException {
      throw Exception('claude-signin-failed');
    } finally {
      await server.close(force: true);
    }
    if (code == null) throw Exception('claude-signin-failed');

    await _exchange({
      'grant_type': 'authorization_code',
      'code': code,
      'state': state,
      'redirect_uri': redirectUri,
      'client_id': clientId,
      'code_verifier': verifier,
    });
  }

  /// A bearer token that is good for at least another minute, refreshed
  /// through the refresh grant when it is not.
  Future<String> validAccessToken() async {
    if (!isSignedIn) throw Exception('claude-signin-required');
    final expiry = prefs.getInt('ClaudeTokenExpiry') ?? 0;
    final access = prefs.getString('ClaudeAccessToken') ?? '';
    if (access.isNotEmpty &&
        DateTime.now()
            .add(const Duration(minutes: 1))
            .millisecondsSinceEpoch <
            expiry) {
      return access;
    }
    await _exchange({
      'grant_type': 'refresh_token',
      'refresh_token': prefs.getString('ClaudeRefreshToken'),
      'client_id': clientId,
    });
    return prefs.getString('ClaudeAccessToken') ?? '';
  }

  Future<void> _exchange(Map<String, dynamic> body) async {
    final Response response;
    try {
      response = await _dio.post(
        tokenEndpoint,
        options: Options(
          headers: {'Content-Type': 'application/json'},
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
        data: json.encode(body),
      );
    } on DioException catch (e) {
      // A rejected refresh token is dead for good — drop it so the UI says
      // "not signed in" instead of failing every request from now on.
      final status = e.response?.statusCode ?? 0;
      if (body['grant_type'] == 'refresh_token' &&
          status >= 400 &&
          status < 500) {
        signOut();
        throw Exception('claude-signin-required');
      }
      throw Exception('claude-signin-failed');
    }

    final data =
        response.data is String ? json.decode(response.data) : response.data;
    final map = data as Map<String, dynamic>;
    final access = map['access_token'] as String?;
    if (access == null || access.isEmpty) {
      throw Exception('claude-signin-failed');
    }
    prefs.setString('ClaudeAccessToken', access);
    final refresh = map['refresh_token'] as String?;
    if (refresh != null && refresh.isNotEmpty) {
      prefs.setString('ClaudeRefreshToken', refresh);
    }
    final expiresIn = map['expires_in'];
    prefs.setInt(
        'ClaudeTokenExpiry',
        DateTime.now()
            .add(Duration(
                seconds: expiresIn is int ? expiresIn : 3600))
            .millisecondsSinceEpoch);
  }

  void signOut() {
    prefs.remove('ClaudeAccessToken');
    prefs.remove('ClaudeRefreshToken');
    prefs.remove('ClaudeTokenExpiry');
  }
}
