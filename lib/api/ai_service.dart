// AI chat for Pro users, running entirely on the user's own
// OpenAI-compatible API key. No app-operated backend, no quota — requests
// go straight from this machine to the configured endpoint.

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
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

    if (!hasByokConfigured) {
      throw Exception('byok-required');
    }

    final userMsg = AiMessage(
      role: 'user',
      content: query,
      timestamp: DateTime.now(),
    );
    _conversationHistory.add(userMsg);
    _saveConversation();

    try {
      final reply = await _sendViaByok();

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
