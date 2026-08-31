// AI chat for Pro users, running entirely on credentials the user brings:
// either their own OpenAI-compatible API key, or their Claude subscription
// via Sign in with Claude. No app-operated backend, no quota — requests go
// straight from this machine to the configured provider.

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:wsl2distromanager/api/claude_auth.dart';
import 'package:wsl2distromanager/api/license_manager.dart';
import 'package:wsl2distromanager/components/helpers.dart';

class AiMessage {
  final String role; // 'user' or 'assistant'
  final String content;
  final DateTime timestamp;

  AiMessage({
    required this.role,
    required this.content,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
      };

  factory AiMessage.fromJson(Map<String, dynamic> json) => AiMessage(
        role: json['role'] as String,
        content: json['content'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
      );
}

class AiService {
  static final AiService _instance = AiService._internal();
  factory AiService() => _instance;
  AiService._internal();

  final Dio _dio = Dio();
  final LicenseManager _license = LicenseManager();

  @visibleForTesting
  Dio get dioForTesting => _dio;

  // Any provider speaking /chat/completions works: OpenAI, Azure proxies,
  // Ollama, LM Studio.
  static const String defaultByokBaseUrl = 'https://api.openai.com/v1';
  static const String defaultByokModel = 'gpt-4o-mini';

  static const String claudeMessagesEndpoint =
      'https://api.anthropic.com/v1/messages';
  static const String defaultClaudeModel = 'claude-sonnet-5';

  /// 'openai' (the BYOK path, default) or 'claude' (Sign in with Claude).
  String get aiProvider => prefs.getString('AiProvider') ?? 'openai';

  void setAiProvider(String provider) {
    if (provider == 'openai') {
      prefs.remove('AiProvider');
    } else {
      prefs.setString('AiProvider', provider);
    }
  }

  bool get usesClaudeAccount => aiProvider == 'claude';

  String get claudeModel {
    final stored = prefs.getString('ClaudeModel')?.trim();
    return (stored != null && stored.isNotEmpty)
        ? stored
        : defaultClaudeModel;
  }

  void setClaudeModel(String model) {
    final trimmed = model.trim();
    if (trimmed.isEmpty) {
      prefs.remove('ClaudeModel');
    } else {
      prefs.setString('ClaudeModel', trimmed);
    }
  }

  String get byokBaseUrl {
    final stored = prefs.getString('ByokBaseUrl')?.trim();
    return (stored != null && stored.isNotEmpty) ? stored : defaultByokBaseUrl;
  }

  String get byokApiKey => prefs.getString('ByokApiKey')?.trim() ?? '';

  String get byokModel {
    final stored = prefs.getString('ByokModel')?.trim();
    return (stored != null && stored.isNotEmpty) ? stored : defaultByokModel;
  }

  /// Whether a key is present. Deliberately not Pro-coupled — Settings can
  /// manage the key regardless; [sendMessage] does the entitlement check.
  bool get hasByokConfigured => byokApiKey.isNotEmpty;

  /// Whether the active provider has what it needs to take a request.
  bool get hasAiConfigured =>
      usesClaudeAccount ? ClaudeAuth().isSignedIn : hasByokConfigured;

  /// The message to show when [hasAiConfigured] is false, matched to the
  /// provider the user actually picked.
  String get configRequiredKey => usesClaudeAccount
      ? 'claude-signin-required-text'
      : 'byok-required-text';

  void setByokBaseUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      prefs.remove('ByokBaseUrl');
    } else {
      prefs.setString('ByokBaseUrl', trimmed);
    }
  }

  void setByokApiKey(String key) {
    final trimmed = key.trim();
    if (trimmed.isEmpty) {
      prefs.remove('ByokApiKey');
    } else {
      prefs.setString('ByokApiKey', trimmed);
    }
  }

  void setByokModel(String model) {
    final trimmed = model.trim();
    if (trimmed.isEmpty) {
      prefs.remove('ByokModel');
    } else {
      prefs.setString('ByokModel', trimmed);
    }
  }

  List<AiMessage> _conversationHistory = [];
  List<AiMessage> get conversationHistory =>
      List.unmodifiable(_conversationHistory);

  /// Load conversation history from prefs on init
  Future<void> init() async {
    final stored = prefs.getString('AiConversation');
    if (stored != null && stored.isNotEmpty) {
      try {
        final list = json.decode(stored) as List;
        _conversationHistory = list
            .map((e) => AiMessage.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        _conversationHistory = [];
      }
    }
  }

  /// Send a message to the AI and return the response
  Future<String> sendMessage(String query) async {
    if (!_license.isPro) {
      throw Exception('pro-required');
    }

    if (!hasAiConfigured) {
      throw Exception(
          usesClaudeAccount ? 'claude-signin-required' : 'byok-required');
    }

    final userMsg = AiMessage(
      role: 'user',
      content: query,
      timestamp: DateTime.now(),
    );
    _conversationHistory.add(userMsg);
    _saveConversation();

    try {
      final reply =
          await (usesClaudeAccount ? _sendViaClaude() : _sendViaByok());

      final assistantMsg = AiMessage(
        role: 'assistant',
        content: reply,
        timestamp: DateTime.now(),
      );
      _conversationHistory.add(assistantMsg);
      _saveConversation();

      return reply;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AI service error: $e');
      }
      // Remove the failed user message from history
      _conversationHistory.removeLast();
      _saveConversation();
      rethrow;
    }
  }

  /// Sends the conversation to the user's own OpenAI-compatible endpoint.
  Future<String> _sendViaByok() async {
    final messages = _conversationHistory
        .take(10)
        .map((m) => {
              'role': m.role == 'user' ? 'user' : 'assistant',
              'content': m.content,
            })
        .toList();

    final Response response;
    try {
      response = await _dio.post(
        '$byokBaseUrl/chat/completions',
        options: Options(
          headers: {
            'Authorization': 'Bearer $byokApiKey',
            'Content-Type': 'application/json',
          },
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 60),
        ),
        data: json.encode({
          'model': byokModel,
          'messages': messages,
        }),
      );
    } on DioException catch (e) {
      if (kDebugMode) {
        debugPrint('BYOK request failed: $e');
      }
      throw Exception('byok-request-failed');
    }

    if (response.statusCode != 200) {
      throw Exception('byok-request-failed');
    }

    final data =
        response.data is String ? json.decode(response.data) : response.data;
    final choices = (data as Map<String, dynamic>)['choices'] as List?;
    final content = choices != null && choices.isNotEmpty
        ? (choices.first['message']?['content'] as String?)
        : null;

    if (content == null || content.trim().isEmpty) {
      throw Exception('byok-empty-response');
    }
    return content.trim();
  }

  /// The Messages API headers: an OAuth bearer token instead of an API key.
  Future<Map<String, String>> _claudeHeaders() async {
    final String token;
    try {
      token = await ClaudeAuth().validAccessToken();
    } catch (_) {
      throw Exception('claude-signin-required');
    }
    return {
      'Authorization': 'Bearer $token',
      'anthropic-version': '2023-06-01',
      'anthropic-beta': 'oauth-2025-04-20',
      'Content-Type': 'application/json',
    };
  }

  /// Model ids the active provider offers, for the settings autocomplete.
  ///
  /// [baseUrl]/[apiKey] let Settings probe the values as typed, before Save;
  /// stored values fill anything omitted. Both provider APIs answer
  /// `GET /models` with `{data: [{id: ...}]}`.
  Future<List<String>> listModels({
    String? provider,
    String? baseUrl,
    String? apiKey,
  }) async {
    final which = provider ?? aiProvider;
    final Response response;
    try {
      if (which == 'claude') {
        response = await _dio.get(
          'https://api.anthropic.com/v1/models',
          options: Options(
            headers: await _claudeHeaders(),
            sendTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 15),
          ),
        );
      } else {
        final url = _orStored(baseUrl, byokBaseUrl);
        response = await _dio.get(
          '$url/models',
          options: Options(
            headers: {'Authorization': 'Bearer ${_orStored(apiKey, byokApiKey)}'},
            sendTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 15),
          ),
        );
      }
    } on DioException catch (e) {
      if (kDebugMode) {
        debugPrint('Model list failed: $e');
      }
      throw Exception('ai-models-failed');
    }
    if (response.statusCode != 200) {
      throw Exception('ai-models-failed');
    }
    final data =
        response.data is String ? json.decode(response.data) : response.data;
    final list = (data as Map<String, dynamic>)['data'] as List?;
    final ids = <String>[
      for (final m in list ?? const [])
        if (m is Map && m['id'] is String) m['id'] as String
    ];
    ids.sort();
    return ids;
  }

  /// One tiny round trip through the active provider, so Settings can prove
  /// the credentials and model name actually work before anyone opens chat.
  Future<void> testConnection({
    String? provider,
    String? baseUrl,
    String? apiKey,
    String? model,
  }) async {
    final which = provider ?? aiProvider;
    const probe = [
      {'role': 'user', 'content': 'Reply with the single word: ok'}
    ];
    final Response response;
    try {
      if (which == 'claude') {
        response = await _dio.post(
          claudeMessagesEndpoint,
          options: Options(
            headers: await _claudeHeaders(),
            sendTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 30),
          ),
          data: json.encode({
            'model': _orStored(model, claudeModel),
            'max_tokens': 16,
            'messages': probe,
          }),
        );
      } else {
        response = await _dio.post(
          '${_orStored(baseUrl, byokBaseUrl)}/chat/completions',
          options: Options(
            headers: {
              'Authorization': 'Bearer ${_orStored(apiKey, byokApiKey)}',
              'Content-Type': 'application/json',
            },
            sendTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 30),
          ),
          data: json.encode({
            'model': _orStored(model, byokModel),
            'max_tokens': 16,
            'messages': probe,
          }),
        );
      }
    } on DioException catch (e) {
      if (kDebugMode) {
        debugPrint('AI test failed: $e');
      }
      throw Exception('ai-test-failed');
    }
    if (response.statusCode != 200) {
      throw Exception('ai-test-failed');
    }
  }

  static String _orStored(String? typed, String stored) {
    final trimmed = typed?.trim() ?? '';
    return trimmed.isNotEmpty ? trimmed : stored;
  }

  /// Sends the conversation to the Messages API on the user's Claude
  /// subscription — an OAuth bearer token instead of an API key.
  Future<String> _sendViaClaude() async {

    final messages = _conversationHistory
        .take(10)
        .map((m) => {
              'role': m.role == 'user' ? 'user' : 'assistant',
              'content': m.content,
            })
        .toList();

    final Response response;
    try {
      response = await _dio.post(
        claudeMessagesEndpoint,
        options: Options(
          headers: await _claudeHeaders(),
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 60),
        ),
        data: json.encode({
          'model': claudeModel,
          'max_tokens': 4096,
          'messages': messages,
        }),
      );
    } on DioException catch (e) {
      if (kDebugMode) {
        debugPrint('Claude request failed: $e');
      }
      throw Exception('claude-request-failed');
    }

    if (response.statusCode != 200) {
      throw Exception('claude-request-failed');
    }

    final data =
        response.data is String ? json.decode(response.data) : response.data;
    final blocks = (data as Map<String, dynamic>)['content'] as List?;
    final text = blocks != null && blocks.isNotEmpty
        ? (blocks.first['text'] as String?)
        : null;

    if (text == null || text.trim().isEmpty) {
      throw Exception('claude-empty-response');
    }
    return text.trim();
  }

  /// Generate a bash script from natural language description
  Future<String> generateScript(String description) async {
    final prompt = '''
Generate a bash script that does the following: $description

Return ONLY the bash script content, no explanations. The script should be safe to run in a WSL distro.
Include comments explaining what each section does.
''';
    return sendMessage(prompt);
  }

  /// Diagnose a WSL error and suggest fixes
  Future<String> diagnoseError(String errorMessage) async {
    final prompt = '''
I'm getting this error in my WSL environment:

$errorMessage

Please explain what's causing this error and provide step-by-step instructions to fix it.
Be specific about which commands to run and which files to edit.
''';
    return sendMessage(prompt);
  }

  /// Generate wsl.conf configuration from natural language request
  Future<String> generateConfig(String request) async {
    final prompt = '''
I need help configuring my WSL environment. Here's what I want:

$request

Please provide the exact wsl.conf settings and any .bashrc modifications needed.
Explain each setting briefly.
''';
    return sendMessage(prompt);
  }

  /// Clear conversation history
  void clearHistory() {
    _conversationHistory.clear();
    prefs.remove('AiConversation');
  }

  void _saveConversation() {
    final data =
        json.encode(_conversationHistory.map((m) => m.toJson()).toList());
    prefs.setString('AiConversation', data);
  }
}
