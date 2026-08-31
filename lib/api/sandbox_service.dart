// A "sandbox": an ordinary WSL distro this app created to be an isolated
// playground for the AI chat. The distro is real WSL — the isolation is that
// the sandbox chat is handed only the `sandbox_*` tools (buildSandboxTools),
// which hardcode this one distro, so the model can run anything *inside* it
// but cannot see the Windows host or any other distro.

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:wsl2distromanager/api/ai_service.dart';
import 'package:wsl2distromanager/api/cancellation.dart';
import 'package:wsl2distromanager/api/app.dart';
import 'package:wsl2distromanager/api/license_manager.dart';
import 'dart:convert';
import 'package:wsl2distromanager/api/mcp/mcp_server.dart';
import 'package:wsl2distromanager/api/mcp/todo_tools.dart';
import 'package:wsl2distromanager/api/todo_store.dart';
import 'package:wsl2distromanager/api/mcp/wsl_mcp_tools.dart';
import 'package:wsl2distromanager/api/mcp/wsl_terminal_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:wsl2distromanager/api/wsl.dart';
import 'package:wsl2distromanager/components/helpers.dart';

class SandboxService {
  SandboxService({WSLApi? api, App? app, Dio? dio})
      : _api = api ?? WSLApi(),
        _app = app ?? App(),
        _dio = dio ?? Dio();

  final WSLApi _api;
  final App _app;
  final Dio _dio;

  /// Registered names carry this prefix so a sandbox is recognisable in the
  /// distro list and never collides with a normal instance.
  static const String prefix = 'wslm-sandbox-';
  static const String _prefsKey = 'SandboxDistros';

  List<String> list() => prefs.getStringList(_prefsKey) ?? <String>[];

  bool isSandbox(String distro) => list().contains(distro);

  void _remember(String distro) {
    final all = list();
    if (!all.contains(distro)) {
      all.add(distro);
      prefs.setStringList(_prefsKey, all);
    }
  }

  void _forget(String distro) {
    final all = list()..remove(distro);
    prefs.setStringList(_prefsKey, all);
  }

  /// The catalog URL for [image] (an exact catalog key), or — when [image]
  /// is null — the newest Ubuntu entry, falling back to the first entry.
  String? _pickImageUrl(Map<String, String> links, String? image) {
    if (links.isEmpty) return null;
    if (image != null && links.containsKey(image)) return links[image];
    final ubuntu = links.entries
        .where((e) => e.key.toLowerCase().contains('ubuntu'))
        .toList()
      ..sort((a, b) => b.key.compareTo(a.key)); // newest label first
    return (ubuntu.isNotEmpty ? ubuntu.first : links.entries.first).value;
  }

  /// The distro name a sandbox called [name] registers under.
  String distroNameFor(String name) =>
      '$prefix${sanitizeDistroName(name)}';

  /// The stage of a sandbox creation in flight, or null when none is.
  ///
  /// App-global, not page state: creation takes minutes (a rootfs download),
  /// and living on the page meant switching tabs lost the progress display —
  /// the work carried on invisibly and its result surfaced nowhere.
  static final ValueNotifier<String?> creationStage =
      ValueNotifier<String?>(null);

  /// Whether a creation is currently running.
  static bool get isCreating => creationStage.value != null;

  /// Download progress of the current creation, 0..1, or null when unknown
  /// or idle — the rootfs is ~700 MB and a bare "downloading" told the user
  /// nothing for minutes.
  static final ValueNotifier<double?> creationProgress =
      ValueNotifier<double?>(null);

  static CancelToken? _creationCancelToken;

  /// Aborts the running creation: the download is torn down and the partial
  /// file deleted.
  static void cancelCreation() => _creationCancelToken?.cancel();

  /// Creation refuses to start below this much free disk. The rootfs plus
  /// its imported VHD comfortably exceed 2 GB, and this machine has already
  /// demonstrated what 0 bytes free does to everything else (2026-08-31).
  static const int minFreeBytes = 3 * 1024 * 1024 * 1024;

  /// Creates a sandbox from a catalog image ([image] is a catalog key;
  /// null = newest Ubuntu): downloads the rootfs and imports it as a new
  /// distro. Returns the registered distro name. Progress is published on
  /// [creationStage] / [creationProgress] so any page (or none) can watch.
  Future<String> createUbuntuSandbox(String name, {String? image}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('A name is required.');
    if (isCreating) throw StateError('A sandbox is already being created.');
    final distro = distroNameFor(trimmed);

    creationStage.value = 'resolving';
    final cancelToken = _creationCancelToken = CancelToken();
    final tmp = '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'wslm-sandbox-${trimmed.hashCode}.tar.gz';
    try {
      // Refuse up front rather than fail mid-download: a full disk here took
      // the whole machine down with it, not just this feature.
      final free = await _api
          .freeSpaceBytes(prefs.getString('DistroPath') ?? Directory.systemTemp.path);
      if (free != null && free < minFreeBytes) {
        throw Exception('sandbox-disk-space');
      }

      final existing = await _api.list(false);
      if (existing.all.any((d) => d.toLowerCase() == distro.toLowerCase())) {
        throw StateError('A distro named "$distro" already exists.');
      }

      final links = await _app.getDistroLinks();
      final url = _pickImageUrl(links, image);
      if (url == null) {
        throw StateError('No matching image is available in the catalog.');
      }

      creationStage.value = 'downloading';
      await _dio.download(url, tmp, cancelToken: cancelToken,
          onReceiveProgress: (received, total) {
        creationProgress.value = total > 0 ? received / total : null;
      });

      creationProgress.value = null;
      creationStage.value = 'importing';
      await _api.import(distro, '', tmp);

      _remember(distro);
      return distro;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) throw const CancelledException();
      rethrow;
    } finally {
      try {
        File(tmp).deleteSync();
      } catch (_) {}
      _creationCancelToken = null;
      creationProgress.value = null;
      creationStage.value = null;
    }
  }

  /// Unregisters a sandbox distro, drops it from the list and deletes its
  /// chat transcript.
  Future<void> deleteSandbox(String distro) async {
    await _api.remove(distro);
    _forget(distro);
    SandboxChat.dropTranscript(distro);
  }
}

/// A chat confined to one sandbox distro: its own persistent transcript and
/// only the `sandbox_*` tools (plus the app's task-queue tools), reusing
/// [AiService]'s provider loop. "All the LLM sees is the inside of the
/// sandbox."
class SandboxChat {
  SandboxChat._(this.distro, {AiService? service})
      : _ai = service ?? AiService() {
    _load();
  }

  @visibleForTesting
  SandboxChat.forTesting(this.distro, {AiService? service})
      : _ai = service ?? AiService();

  /// One live instance per sandbox, so closing and reopening the panel comes
  /// back to the same conversation instead of a fresh empty one.
  static final Map<String, SandboxChat> _instances = {};
  factory SandboxChat.of(String distro) =>
      _instances.putIfAbsent(distro, () => SandboxChat._(distro));

  static String _prefsKeyFor(String distro) => 'SandboxChat_$distro';

  /// Sandboxes that have a stored transcript — the "last sessions" list.
  static List<String> sessions() => SandboxService()
      .list()
      .where((d) =>
          _instances[d]?.history.isNotEmpty == true ||
          (prefs.getString(_prefsKeyFor(d))?.isNotEmpty ?? false))
      .toList();

  /// Deletes the stored transcript (used when the sandbox itself goes).
  static void dropTranscript(String distro) {
    _instances.remove(distro);
    prefs.remove(_prefsKeyFor(distro));
  }

  final String distro;
  final AiService _ai;
  final List<AiMessage> _history = [];

  void _load() {
    final stored = prefs.getString(_prefsKeyFor(distro));
    if (stored == null || stored.isEmpty) return;
    try {
      final list = json.decode(stored) as List;
      _history
        ..clear()
        ..addAll(
            list.map((e) => AiMessage.fromJson(e as Map<String, dynamic>)));
    } catch (_) {}
  }

  void _persist() {
    prefs.setString(_prefsKeyFor(distro),
        json.encode(_history.map((m) => m.toJson()).toList()));
  }

  List<McpTool>? _toolsOverride;
  List<McpTool> get _tools => _toolsOverride ??= [
        ...buildSandboxTools(
            WSLApi(), WslTerminalManager(wslApi: WSLApi()), distro),
        // The task queue works in the sandbox chat too — the todo tools touch
        // only the app's own list, never the host.
        ...buildTodoTools(TodoStore.instance),
      ];

  @visibleForTesting
  set toolsForTesting(List<McpTool> value) => _toolsOverride = value;

  List<AiMessage> get history => List.unmodifiable(_history);

  bool get canSend => LicenseManager().isPro && _ai.hasAiConfigured;

  String get _systemPrompt => '''
You are an assistant confined to a single sandboxed Linux environment (a WSL distro named "$distro"). Everything you do happens INSIDE it through the sandbox_* tools — you cannot see or affect the user's Windows machine or any other distro, and there is no such thing to reach. Use sandbox_run_command to inspect and work inside the sandbox. After acting, say briefly what you did. Keep answers concise.
You also have a task queue (todo_list, todo_add, todo_set_done, todo_remove). When the user asks you to work through their tasks, read the list, do each one inside the sandbox, and mark it done with todo_set_done as soon as you finish it.''';

  Future<String> send(String query,
      {void Function()? onUpdate, CancelSignal? cancel}) async {
    if (!LicenseManager().isPro) throw Exception('pro-required');
    if (!_ai.hasAiConfigured) {
      throw Exception(_ai.usesClaudeAccount
          ? 'claude-signin-required'
          : 'byok-required');
    }
    _history.add(AiMessage(
        role: 'user', content: query, timestamp: DateTime.now()));
    _persist();
    onUpdate?.call();
    try {
      final reply = await _ai.runAgentOn(_history, _tools,
          onUpdate: onUpdate,
          systemPrompt: _systemPrompt,
          persist: _persist,
          cancel: cancel);
      _history.add(AiMessage(
          role: 'assistant', content: reply, timestamp: DateTime.now()));
      _persist();
      onUpdate?.call();
      return reply;
    } on CancelledException {
      // A cancel keeps what already happened; only the reply is absent.
      _persist();
      rethrow;
    } catch (e) {
      // Roll back to the last user turn so a retry is clean.
      while (_history.isNotEmpty && _history.last.role != 'user') {
        _history.removeLast();
      }
      if (_history.isNotEmpty) _history.removeLast();
      _persist();
      rethrow;
    }
  }

  void clear() {
    _history.clear();
    _persist();
  }
}
