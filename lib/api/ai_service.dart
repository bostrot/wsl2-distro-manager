// AI chat for Pro users, running entirely on credentials the user brings:
// their own OpenAI-compatible API key. No app-operated backend, no quota —
// requests go straight from this machine to the configured provider.
//
// There is deliberately no "Sign in with Claude" path. Anthropic's terms do
// not let third-party apps offer Claude.ai login or route requests through a
// Free/Pro/Max subscription (code.claude.com/docs/en/legal-and-compliance);
// the sanctioned route for an app like this one is an API key from the Claude
// Console, which is what the key field is for.

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:wsl2distromanager/api/cancellation.dart';
import 'package:wsl2distromanager/api/license_manager.dart';
import 'package:wsl2distromanager/api/mcp/mcp_server.dart';
import 'package:wsl2distromanager/api/mcp/todo_tools.dart';
import 'package:wsl2distromanager/api/mcp/wsl_mcp_tools.dart';
import 'package:wsl2distromanager/api/mcp/wsl_terminal_manager.dart';
import 'package:wsl2distromanager/api/todo_store.dart';
import 'package:wsl2distromanager/api/vm/vm_platform.dart';
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

  /// Whether the provider has what it needs to take a request.
  bool get hasAiConfigured => hasByokConfigured;

  /// The message to show when [hasAiConfigured] is false.
  String get configRequiredKey => 'byok-required-text';

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

  /// Preference keys of the removed "Sign in with Claude" provider. The
  /// OAuth tokens among them are credentials, so they must not linger in
  /// prefs once the code that used them is gone.
  @visibleForTesting
  static const List<String> retiredClaudePrefKeys = [
    'AiProvider',
    'ClaudeOAuthClientId',
    'ClaudeModel',
    'ClaudeAccessToken',
    'ClaudeRefreshToken',
    'ClaudeTokenExpiry',
  ];

  /// One-time cleanup of [retiredClaudePrefKeys]; harmless when none are set.
  /// Runs at startup and again from [init], so a profile written by a build
  /// that still had the provider is scrubbed on the first launch after the
  /// update, not the first chat.
  static void purgeRetiredClaudePrefs() {
    for (final key in retiredClaudePrefKeys) {
      prefs.remove(key);
    }
  }

  /// Load conversation history from prefs on init
  Future<void> init() async {
    purgeRetiredClaudePrefs();
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
  /// Tools the chat can call. Defaults to the same registry the MCP server
  /// exposes, so the assistant can actually inspect and operate the user's
  /// WSL instead of guessing — a scoped instance (the sandbox chat) passes a
  /// narrower list.
  List<McpTool>? _tools;
  List<McpTool> get tools => _tools ??= [
        ...buildWslMcpTools(vmBackend(), WslTerminalManager()),
        ...buildTodoTools(TodoStore.instance),
      ];

  @visibleForTesting
  set toolsForTesting(List<McpTool> value) => _tools = value;

  /// System prompt: says what the assistant is and that its tools act on the
  /// user's real machine, so it uses them instead of answering from nothing
  /// (the "I don't have access to your system" reply the tools exist to fix).
  String get _systemPrompt => isAppleHost
      ? '''
You are the AI assistant built into WSL Manager on macOS, a GUI for managing native virtual machines via Apple's Virtualization framework. You have tools that operate on the user's REAL VMs on this Mac. Use them to answer questions and carry out tasks rather than guessing or claiming you lack access — e.g. call wsl_list_distros to see the VMs, wsl_run_command to run something inside a running VM (over SSH).
Creating a Linux VM: it MUST boot from something — a blank disk boots into nothing and stops immediately. Always give vm_create_linux a boot source: pass a "catalog" id (call vm_list_images first) or an image_path/iso_path. When the user wants a usable system (a user account, a password, software installed), pick a catalog entry marked as a cloud image (e.g. "debian-13-cloud"): it boots ready to use and reachable over SSH with no manual install, so wsl_run_command and service recipes work right after vm_start. Installer ISOs (the "virt", "standard", "netinst" and Ubuntu Server entries) need the user to click through an install in the VM window first — never promise automated setup on top of one. Do NOT create a VM with no boot source and then try to start it; the tool now refuses that.
Setting a user password or running setup only works once the VM is running AND reachable over SSH (a cloud image is; a bare installer ISO is not until installed). Installing a local service (database, storage, broker): use wsl_list_recipes then wsl_install_service against a running, reachable VM.
Docker and Podman containers are a separate thing from VMs and distros, with their own tools: container_list, container_start/stop/restart, container_logs, container_exec, container_inspect. Use those for anything about containers, and never wsl_* — removing a container (container_remove) is permanent and confirm-gated like unregistering an instance.
Prefer read-only tools to inspect state before acting. Destructive actions (wsl_unregister_distro) need explicit user intent and their confirm flag. After you run a command or change something, say briefly what you did. Keep answers concise and in the user's language.'''
      : '''
You are the AI assistant built into WSL Distro Manager, a Windows GUI for managing WSL2 Linux distributions. You have tools that operate on the user's REAL WSL installation on this machine. Use them to answer questions and carry out tasks rather than guessing or claiming you lack access — e.g. call wsl_list_distros to see installed distros, wsl_list_catalog / wsl_list_online_distros for what can be installed, wsl_run_command to run something inside a distro.
Docker and Podman containers are a separate thing from VMs and distros, with their own tools: container_list, container_start/stop/restart, container_logs, container_exec, container_inspect. Use those for anything about containers, and never wsl_* — removing a container (container_remove) is permanent and confirm-gated like unregistering an instance.
Prefer read-only tools to inspect state before acting. Destructive actions (wsl_unregister_distro) need explicit user intent and their confirm flag. After you run a command or change something, say briefly what you did. Keep answers concise and in the user's language.
You also have a task queue (todo_list, todo_add, todo_set_done, todo_remove). When the user asks you to work through their tasks, read the list, do each one with your tools, and mark it done with todo_set_done as soon as you finish it.''';

  /// How many tool round-trips one message may take before the loop stops.
  ///
  /// A backstop against a pathological loop, not a budget: each iteration is
  /// one provider request on the user's own credentials, Cancel is always
  /// live, and the task runner stops itself on no-progress rounds — so this
  /// only needs to be high enough that real work never hits it. A real
  /// Docker-on-Alpine provisioning run burned through 8 and then 24; the
  /// transcript survives either way, so "continue" picks up if 100 is ever
  /// reached.
  static const int _maxToolIterations = 100;

  /// Tool output is fed back to the model; a multi-megabyte `find /` would
  /// blow the context, so it is capped.
  static const int _maxToolResultChars = 6000;

  /// How many prior user/assistant turns one request carries. The transcript
  /// itself is unbounded (it persists across sessions now); what goes over
  /// the wire is not — the `take(10)` cap was lost when tool-use landed and
  /// every request grew with the conversation forever.
  static const int _maxHistoryMessages = 30;

  /// Character budget for the same history slice, so thirty short turns pass
  /// but thirty pasted logs do not.
  static const int _maxHistoryChars = 30000;

  /// In-run message-list budget: past this many entries, the *oldest* tool
  /// results are elided (structure kept — the protocol requires the
  /// call/result pairing to stay intact).
  static const int _maxRunMessages = 40;

  /// Live progress of the current agent run ("step 3 · 12.4k tokens"), or
  /// null when idle. The panel renders it next to the spinner so a long run
  /// is visibly moving rather than hanging.
  final ValueNotifier<String?> runStatus = ValueNotifier<String?>(null);

  int _runTokens = 0;

  void _reportStep(int iteration) {
    runStatus.value = _runTokens > 0
        ? 'step ${iteration + 1} · ${(_runTokens / 1000).toStringAsFixed(1)}k tokens'
        : 'step ${iteration + 1}';
  }

  void _addUsage(Map<String, dynamic> data) {
    final usage = data['usage'];
    if (usage is! Map) return;
    final total = usage['total_tokens'];
    if (total is num) _runTokens += total.toInt();
  }

  Future<String> sendMessage(String query,
      {void Function()? onUpdate, CancelSignal? cancel}) async {
    if (!_license.isPro) {
      throw Exception('pro-required');
    }

    if (!hasAiConfigured) {
      throw Exception('byok-required');
    }

    final userMsg = AiMessage(
      role: 'user',
      content: query,
      timestamp: DateTime.now(),
    );
    _conversationHistory.add(userMsg);
    _saveConversation();

    return _completeFromHistory(onUpdate: onUpdate, cancel: cancel);
  }

  /// Re-run the agent over the transcript as it stands — the retry after a
  /// failed send, whose user message is already in the history.
  Future<String> retryLast(
      {void Function()? onUpdate, CancelSignal? cancel}) async {
    if (!_license.isPro) {
      throw Exception('pro-required');
    }
    if (!hasAiConfigured) {
      throw Exception('byok-required');
    }
    return _completeFromHistory(onUpdate: onUpdate, cancel: cancel);
  }

  Future<String> _completeFromHistory(
      {void Function()? onUpdate, CancelSignal? cancel}) async {
    try {
      final reply = await runAgent(tools, onUpdate: onUpdate, cancel: cancel);

      final assistantMsg = AiMessage(
        role: 'assistant',
        content: reply,
        timestamp: DateTime.now(),
      );
      _conversationHistory.add(assistantMsg);
      _saveConversation();

      return reply;
    } on CancelledException {
      // The user got what they asked for. What already ran, ran — the tool
      // notes stay in the transcript; only the never-written reply is absent.
      _saveConversation();
      rethrow;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AI service error: $e');
      }
      // Roll back any partial tool notes added mid-run, but KEEP the user's
      // message: the panel shows a retry that re-runs it (retryLast). The
      // history ends on the user turn, so a retry starts clean without
      // making the user retype the question.
      while (_conversationHistory.isNotEmpty &&
          _conversationHistory.last.role != 'user') {
        _conversationHistory.removeLast();
      }
      _saveConversation();
      rethrow;
    }
  }

  /// Records a tool call in the transcript as a compact note (UI only — these
  /// are never replayed to the provider), and pings [onUpdate] so the panel
  /// can show it live.
  void _noteTool(List<AiMessage> transcript, void Function()? persist,
      String label, void Function()? onUpdate) {
    transcript.add(AiMessage(
      role: 'tool',
      content: label,
      timestamp: DateTime.now(),
    ));
    persist?.call();
    onUpdate?.call();
  }

  void _noteAssistant(List<AiMessage> transcript, void Function()? persist,
      String text, void Function()? onUpdate) {
    if (text.trim().isEmpty) return;
    transcript.add(AiMessage(
      role: 'assistant',
      content: text.trim(),
      timestamp: DateTime.now(),
    ));
    persist?.call();
    onUpdate?.call();
  }

  /// Executes one tool by name and returns its output (or an error string the
  /// model can read and recover from), capped in size.
  Future<String> _executeTool(
      List<McpTool> toolList, String name, Map<String, dynamic> args) async {
    McpTool? tool;
    for (final t in toolList) {
      if (t.name == name) {
        tool = t;
        break;
      }
    }
    if (tool == null) return 'Error: unknown tool "$name".';
    String out;
    try {
      out = await tool.handler(args);
    } catch (e) {
      return 'Error: $e';
    }
    if (out.length > _maxToolResultChars) {
      out = '${out.substring(0, _maxToolResultChars)}\n…(truncated)';
    }
    return out;
  }

  /// Runs the current provider as an agent over [toolList] against the main
  /// chat transcript.
  @visibleForTesting
  Future<String> runAgent(List<McpTool> toolList,
          {void Function()? onUpdate,
          String? systemPrompt,
          CancelSignal? cancel}) =>
      runAgentOn(_conversationHistory, toolList,
          onUpdate: onUpdate,
          systemPrompt: systemPrompt,
          cancel: cancel,
          persist: _saveConversation);

  /// Runs the agent loop against an arbitrary [transcript] — the same core
  /// the main chat uses, exposed so a scoped conversation (the sandbox chat,
  /// with its own history and its own locked-down tools) reuses it instead of
  /// duplicating the provider plumbing. [persist] is called whenever the
  /// transcript grows; pass null for an ephemeral chat.
  ///
  /// [cancel] genuinely stops the run: it is checked before every provider
  /// request and every tool execution, and it aborts the in-flight HTTP call
  /// — Cancel used to only make the UI *look* stopped while tools kept
  /// running on the real machine and requests kept billing the user's key.
  Future<String> runAgentOn(
    List<AiMessage> transcript,
    List<McpTool> toolList, {
    void Function()? onUpdate,
    String? systemPrompt,
    void Function()? persist,
    CancelSignal? cancel,
  }) async {
    _runTokens = 0;
    runStatus.value = null;
    try {
      return await _runByokAgent(transcript, toolList,
          onUpdate: onUpdate,
          persist: persist,
          cancel: cancel,
          systemPrompt: systemPrompt ?? _systemPrompt);
    } finally {
      runStatus.value = null;
      streamingText.value = '';
    }
  }

  /// A dio token that fires when [cancel] does, so an in-flight request is
  /// torn down instead of merely having its answer ignored.
  CancelToken? _dioTokenFor(CancelSignal? cancel) {
    if (cancel == null) return null;
    final token = CancelToken();
    cancel.onCancel(token.cancel);
    return token;
  }

  /// Text of the reply currently being streamed, live, so the panel can
  /// render tokens as they arrive instead of a spinner until the very end.
  /// Empty when nothing is streaming.
  final ValueNotifier<String> streamingText = ValueNotifier<String>('');

  DateTime _lastStreamEmit = DateTime.fromMillisecondsSinceEpoch(0);

  /// Publishes a streaming delta, repainting at most every ~80ms — token
  /// deltas arrive far faster than a rebuild is worth.
  void _emitStreamDelta(String full, void Function()? onUpdate) {
    streamingText.value = full;
    final now = DateTime.now();
    if (now.difference(_lastStreamEmit).inMilliseconds >= 80) {
      _lastStreamEmit = now;
      onUpdate?.call();
    }
  }

  /// Every `data:` JSON payload of an SSE response, in order — or, when the
  /// body is not SSE at all (a mocked test, a proxy that ignored
  /// `stream: true`), the whole body parsed as one payload. That fallback is
  /// what keeps streaming an upgrade instead of a new hard requirement.
  Future<List<Map<String, dynamic>>> _ssePayloads(Response response) async {
    final body = response.data;
    if (body is! ResponseBody) {
      // Non-stream responseType — already-decoded JSON.
      final data = body is String ? json.decode(body) : body;
      return [data as Map<String, dynamic>];
    }
    final payloads = <Map<String, dynamic>>[];
    final buffer = StringBuffer();
    var sawSse = false;
    await for (final line in utf8.decoder
        .bind(body.stream)
        .transform(const LineSplitter())) {
      if (line.startsWith('data:')) {
        sawSse = true;
        final data = line.substring(5).trim();
        if (data.isEmpty || data == '[DONE]') continue;
        try {
          payloads.add(json.decode(data) as Map<String, dynamic>);
        } catch (_) {}
        continue;
      }
      // `event:` lines, comments and blanks are framing; anything else is a
      // plain JSON body arriving in pieces.
      if (!sawSse) buffer.write(line);
    }
    if (!sawSse && buffer.isNotEmpty) {
      payloads.add(json.decode(buffer.toString()) as Map<String, dynamic>);
    }
    return payloads;
  }

  /// Assembles one OpenAI chat message out of [response] — streamed deltas
  /// or a complete body alike. Returns the same map shape the non-streaming
  /// code always consumed: {'message': ..., with usage already accounted}.
  Future<Map<String, dynamic>?> _byokMessage(
      Response response, void Function()? onUpdate) async {
    final payloads = await _ssePayloads(response);
    // Complete-body case: exactly the old shape.
    if (payloads.length == 1 && payloads.single.containsKey('choices')) {
      final only = payloads.single;
      final choices = only['choices'] as List?;
      final message = choices != null && choices.isNotEmpty
          ? (choices.first as Map)['message']
          : null;
      if (message is Map) {
        _addUsage(only);
        return Map<String, dynamic>.from(message);
      }
    }
    // Streamed case: fold the deltas.
    final content = StringBuffer();
    final toolCalls = <int, Map<String, dynamic>>{};
    for (final payload in payloads) {
      _addUsage(payload);
      final choices = payload['choices'] as List?;
      if (choices == null || choices.isEmpty) continue;
      final delta = (choices.first as Map)['delta'];
      if (delta is! Map) continue;
      final text = delta['content'];
      if (text is String && text.isNotEmpty) {
        content.write(text);
        _emitStreamDelta(content.toString(), onUpdate);
      }
      final calls = delta['tool_calls'];
      if (calls is List) {
        for (final c in calls) {
          if (c is! Map) continue;
          final index = (c['index'] as num?)?.toInt() ?? 0;
          final entry = toolCalls.putIfAbsent(
              index,
              () => {
                    'id': '',
                    'type': 'function',
                    'function': {'name': '', 'arguments': ''},
                  });
          if (c['id'] is String && (c['id'] as String).isNotEmpty) {
            entry['id'] = c['id'];
          }
          final fn = c['function'];
          if (fn is Map) {
            final f = entry['function'] as Map<String, dynamic>;
            if (fn['name'] is String && (fn['name'] as String).isNotEmpty) {
              f['name'] = '${f['name']}${fn['name']}';
            }
            if (fn['arguments'] is String) {
              f['arguments'] = '${f['arguments']}${fn['arguments']}';
            }
          }
        }
      }
    }
    if (content.isEmpty && toolCalls.isEmpty) return null;
    final ordered = toolCalls.keys.toList()..sort();
    return {
      'role': 'assistant',
      'content': content.isEmpty ? null : content.toString(),
      if (toolCalls.isNotEmpty)
        'tool_calls': [for (final i in ordered) toolCalls[i]],
    };
  }

  /// True when [e] is dio reporting our own cancellation, which the loops
  /// convert to [CancelledException] rather than a request failure.
  static bool _isDioCancel(DioException e) =>
      e.type == DioExceptionType.cancel;

  /// The prior transcript as provider messages: user and assistant turns only
  /// (the `tool` notes are UI-side and would not be valid protocol messages).
  /// Capped from the *end* — most recent first to survive — by both message
  /// count and characters, so a persistent conversation cannot grow every
  /// request without bound.
  List<Map<String, dynamic>> _historyMessages(List<AiMessage> transcript) =>
      capTranscript(transcript)
          .map((m) => {'role': m.role, 'content': m.content})
          .toList();

  @visibleForTesting
  static List<AiMessage> capTranscript(List<AiMessage> transcript) {
    final relevant = transcript
        .where((m) => m.role == 'user' || m.role == 'assistant')
        .toList();
    final kept = <AiMessage>[];
    var chars = 0;
    for (final m in relevant.reversed) {
      if (kept.length >= _maxHistoryMessages) break;
      if (kept.isNotEmpty && chars + m.content.length > _maxHistoryChars) {
        break;
      }
      kept.add(m);
      chars += m.content.length;
    }
    return kept.reversed.toList();
  }

  /// Elides the content of tool results that have scrolled far enough back in
  /// this run's message list, keeping every entry (the protocol requires the
  /// call/result pairing to stay) but not its bulk.
  static void _elideOldToolResults(List<Map<String, dynamic>> messages) {
    if (messages.length <= _maxRunMessages) return;
    const marker = '(elided earlier tool output)';
    final cutoff = messages.length - _maxRunMessages;
    for (var i = 0; i < cutoff; i++) {
      final m = messages[i];
      // {role: tool, content: <big string>}
      if (m['role'] == 'tool' &&
          m['content'] is String &&
          (m['content'] as String).length > marker.length) {
        m['content'] = marker;
      }
    }
  }

  /// OpenAI function-calling specs for [toolList].
  List<Map<String, dynamic>> _openAiToolSpecs(List<McpTool> toolList) =>
      toolList
          .map((t) => {
                'type': 'function',
                'function': {
                  'name': t.name,
                  'description': t.description,
                  'parameters': t.inputSchema,
                },
              })
          .toList();

  /// The OpenAI-compatible agent loop.
  Future<String> _runByokAgent(
      List<AiMessage> transcript, List<McpTool> toolList,
      {void Function()? onUpdate,
      void Function()? persist,
      CancelSignal? cancel,
      required String systemPrompt}) async {
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': systemPrompt},
      ..._historyMessages(transcript),
    ];
    final toolSpecs = _openAiToolSpecs(toolList);

    for (var i = 0; i < _maxToolIterations; i++) {
      cancel?.throwIfCancelled();
      _reportStep(i);
      _elideOldToolResults(messages);
      final Map<String, dynamic>? message;
      try {
        // `stream: true` + a stream response type: tokens render as they
        // arrive. Providers (and mocks) that answer with a plain JSON body
        // instead are folded back in by [_ssePayloads]'s fallback.
        final response = await _dio.post(
          '$byokBaseUrl/chat/completions',
          cancelToken: _dioTokenFor(cancel),
          options: Options(
            responseType: ResponseType.stream,
            headers: {
              'Authorization': 'Bearer $byokApiKey',
              'Content-Type': 'application/json',
            },
            sendTimeout: const Duration(seconds: 30),
            receiveTimeout: const Duration(seconds: 120),
          ),
          data: json.encode({
            'model': byokModel,
            'stream': true,
            'messages': messages,
            if (toolSpecs.isNotEmpty) 'tools': toolSpecs,
            if (toolSpecs.isNotEmpty) 'tool_choice': 'auto',
          }),
        );
        message = await _byokMessage(response, onUpdate);
      } on DioException catch (e) {
        if (_isDioCancel(e)) throw const CancelledException();
        if (kDebugMode) debugPrint('BYOK request failed: $e');
        throw Exception('byok-request-failed');
      }
      final toolCalls = message?['tool_calls'] as List?;
      final content = message?['content'] as String?;

      if (toolCalls == null || toolCalls.isEmpty) {
        streamingText.value = '';
        if (content == null || content.trim().isEmpty) {
          throw Exception('byok-empty-response');
        }
        return content.trim();
      }

      // A model that narrates before calling ("Let me check…") — surface it.
      streamingText.value = '';
      if (content != null && content.trim().isNotEmpty) {
        _noteAssistant(transcript, persist, content, onUpdate);
      }
      messages.add(message!);

      for (final call in toolCalls) {
        final fn = (call as Map)['function'] as Map?;
        final name = fn?['name'] as String? ?? '';
        final rawArgs = fn?['arguments'];
        Map<String, dynamic> parsedArgs = {};
        if (rawArgs is String && rawArgs.trim().isNotEmpty) {
          try {
            parsedArgs = json.decode(rawArgs) as Map<String, dynamic>;
          } catch (_) {}
        } else if (rawArgs is Map) {
          parsedArgs = Map<String, dynamic>.from(rawArgs);
        }
        cancel?.throwIfCancelled();
        _noteTool(transcript, persist, name, onUpdate);
        final result = await _executeTool(toolList, name, parsedArgs);
        messages.add({
          'role': 'tool',
          'tool_call_id': call['id'],
          'content': result,
        });
      }
    }
    // Ran out of tool iterations without a final answer.
    return _toolLimitMessage;
  }

  static const String _toolLimitMessage =
      'I ran several tools but could not finish within the step limit. '
      'Please narrow the request or ask me to continue.';

  /// Model ids the provider offers, for the settings autocomplete.
  ///
  /// [baseUrl]/[apiKey] let Settings probe the values as typed, before Save;
  /// stored values fill anything omitted. The API answers `GET /models` with
  /// `{data: [{id: ...}]}`.
  Future<List<String>> listModels({
    String? baseUrl,
    String? apiKey,
  }) async {
    final Response response;
    try {
      final url = _orStored(baseUrl, byokBaseUrl);
      response = await _dio.get(
        '$url/models',
        options: Options(
          headers: {'Authorization': 'Bearer ${_orStored(apiKey, byokApiKey)}'},
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
        ),
      );
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

  /// One tiny round trip through the provider, so Settings can prove the
  /// credentials and model name actually work before anyone opens chat.
  Future<void> testConnection({
    String? baseUrl,
    String? apiKey,
    String? model,
  }) async {
    const probe = [
      {'role': 'user', 'content': 'Reply with the single word: ok'}
    ];
    final Response response;
    try {
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
