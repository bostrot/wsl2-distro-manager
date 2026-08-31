// A "sandbox": an ordinary WSL distro this app created to be an isolated
// playground for the AI chat. The distro is real WSL — the isolation is that
// the sandbox chat is handed only the `sandbox_*` tools (buildSandboxTools),
// which hardcode this one distro, so the model can run anything *inside* it
// but cannot see the Windows host or any other distro.

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:wsl2distromanager/api/ai_service.dart';
import 'package:wsl2distromanager/api/app.dart';
import 'package:wsl2distromanager/api/license_manager.dart';
import 'package:wsl2distromanager/api/mcp/mcp_server.dart';
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

  /// Picks the catalog's best Ubuntu entry (falling back to the first entry).
  String? _pickUbuntuUrl(Map<String, String> links) {
    if (links.isEmpty) return null;
    final ubuntu = links.entries
        .where((e) => e.key.toLowerCase().contains('ubuntu'))
        .toList()
      ..sort((a, b) => b.key.compareTo(a.key)); // newest label first
    return (ubuntu.isNotEmpty ? ubuntu.first : links.entries.first).value;
  }

  /// The distro name a sandbox called [name] registers under.
  String distroNameFor(String name) =>
      '$prefix${sanitizeDistroName(name)}';

  /// Creates an Ubuntu sandbox: downloads the catalog rootfs and imports it as
  /// a new distro. Returns the registered distro name.
  Future<String> createUbuntuSandbox(String name,
      {void Function(String stage)? onProgress}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('A name is required.');
    final distro = distroNameFor(trimmed);

    final existing = await _api.list(false);
    if (existing.all.any((d) => d.toLowerCase() == distro.toLowerCase())) {
      throw StateError('A distro named "$distro" already exists.');
    }

    onProgress?.call('resolving');
    final links = await _app.getDistroLinks();
    final url = _pickUbuntuUrl(links);
    if (url == null) {
      throw StateError('No Ubuntu image is available in the catalog.');
    }

    onProgress?.call('downloading');
    final tmp = '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'wslm-sandbox-${trimmed.hashCode}.tar.gz';
    await _dio.download(url, tmp);

    onProgress?.call('importing');
    await _api.import(distro, '', tmp);
    try {
      File(tmp).deleteSync();
    } catch (_) {}

    _remember(distro);
    return distro;
  }

  /// Unregisters a sandbox distro and drops it from the list.
  Future<void> deleteSandbox(String distro) async {
    await _api.remove(distro);
    _forget(distro);
  }
}

/// A chat confined to one sandbox distro: its own transcript and only the
/// `sandbox_*` tools, reusing [AiService]'s provider loop. "All the LLM sees
/// is the inside of the sandbox."
class SandboxChat {
  SandboxChat(this.distro, {AiService? service})
      : _ai = service ?? AiService();

  final String distro;
  final AiService _ai;
  final List<AiMessage> _history = [];

  List<McpTool>? _toolsOverride;
  List<McpTool> get _tools =>
      _toolsOverride ??=
          buildSandboxTools(WSLApi(), WslTerminalManager(wslApi: WSLApi()), distro);

  @visibleForTesting
  set toolsForTesting(List<McpTool> value) => _toolsOverride = value;

  List<AiMessage> get history => List.unmodifiable(_history);

  bool get canSend => LicenseManager().isPro && _ai.hasAiConfigured;

  String get _systemPrompt => '''
You are an assistant confined to a single sandboxed Linux environment (a WSL distro named "$distro"). Everything you do happens INSIDE it through the sandbox_* tools — you cannot see or affect the user's Windows machine or any other distro, and there is no such thing to reach. Use sandbox_run_command to inspect and work inside the sandbox. After acting, say briefly what you did. Keep answers concise.''';

  Future<String> send(String query, {void Function()? onUpdate}) async {
    if (!LicenseManager().isPro) throw Exception('pro-required');
    if (!_ai.hasAiConfigured) {
      throw Exception(_ai.usesClaudeAccount
          ? 'claude-signin-required'
          : 'byok-required');
    }
    _history.add(AiMessage(
        role: 'user', content: query, timestamp: DateTime.now()));
    onUpdate?.call();
    try {
      final reply = await _ai.runAgentOn(_history, _tools,
          onUpdate: onUpdate, systemPrompt: _systemPrompt);
      _history.add(AiMessage(
          role: 'assistant', content: reply, timestamp: DateTime.now()));
      onUpdate?.call();
      return reply;
    } catch (e) {
      // Roll back to the last user turn so a retry is clean.
      while (_history.isNotEmpty && _history.last.role != 'user') {
        _history.removeLast();
      }
      if (_history.isNotEmpty) _history.removeLast();
      rethrow;
    }
  }

  void clear() => _history.clear();
}
