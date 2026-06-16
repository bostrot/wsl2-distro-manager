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

  // n8n webhook endpoint for AI queries
  String get _backendUrl => 'https://n8n.aachen.dev/webhook/wsl-manager/query';

  // Monthly query limit per subscriber
  static const int monthlyLimit = 50;

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

    // Reset query count on new month
    final lastReset = prefs.getString('AiQueryLastReset');
    final now = DateTime.now();
    if (lastReset == null ||
        DateTime.parse(lastReset).month != now.month ||
        DateTime.parse(lastReset).year != now.year) {
      prefs.setInt('AiQueryCount', 0);
      prefs.setString('AiQueryLastReset', '${now.year}-${now.month}');
    }
  }

  /// Check if user has remaining queries this month
  bool get hasQueriesRemaining {
    final count = prefs.getInt('AiQueryCount') ?? 0;
    return count < monthlyLimit;
  }

  int get queriesUsed => prefs.getInt('AiQueryCount') ?? 0;
  int get queriesRemaining => monthlyLimit - queriesUsed;

  /// Send a message to the AI and return the response
  Future<String> sendMessage(String query) async {
    if (!_license.isPro) {
      throw Exception('pro-required');
    }

    if (!hasQueriesRemaining) {
      throw Exception('query-limit-reached');
    }

    // Add user message to history
    final userMsg = AiMessage(
      role: 'user',
      content: query,
      timestamp: DateTime.now(),
    );
    _conversationHistory.add(userMsg);
    _saveConversation();

    try {
      // Build context from recent conversation (last 10 messages for context window)
      final contextMessages = _conversationHistory
          .take(10)
          .map((m) => '${m.role}: ${m.content}')
          .join('\n');

      final response = await _dio.post(
        _backendUrl,
        options: Options(
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 60),
        ),
        data: json.encode({
          'query': query,
          'context': contextMessages,
          'license_key': prefs.getString('LicenseKey') ?? '',
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.data) as Map<String, dynamic>;
        final reply = data['reply'] as String? ?? 'No response from AI.';

        // Increment query count
        prefs.setInt('AiQueryCount', queriesUsed + 1);

        // Add assistant message to history
        final assistantMsg = AiMessage(
          role: 'assistant',
          content: reply,
          timestamp: DateTime.now(),
        );
        _conversationHistory.add(assistantMsg);
        _saveConversation();

        return reply;
      } else {
        throw Exception('api-error');
      }
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
