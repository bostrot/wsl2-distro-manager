// Persistent, session-based terminal control for the WSL MCP tools — as
// opposed to wsl_mcp_tools.dart's wsl_run_command, which runs one command
// and returns once it exits. A session keeps a real WSL shell process alive
// across multiple MCP calls, so a client can start an interactive/long-running
// program, send it input over time, and poll for output — e.g. a REPL, a
// build watcher, or any command that needs stdin after starting.
//
// Built on WSLApi.startShell(), which is the exact same "spawn `wsl -d X -u
// root` with no command, so it drops into the distro's default shell reading
// from stdin" primitive that execCmds()/runCmds() already use elsewhere in
// this codebase — not a new, unproven way of talking to WSL.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:wsl2distromanager/api/wsl.dart';

class WslTerminalSession {
  final String id;
  final String distribution;
  final String user;
  final Process process;
  final DateTime startedAt;

  final StringBuffer _output = StringBuffer();
  int _readOffset = 0;
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;
  bool _closed = false;

  WslTerminalSession({
    required this.id,
    required this.distribution,
    required this.user,
    required this.process,
  }) : startedAt = DateTime.now() {
    _stdoutSub = process.stdout
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(_output.write);
    _stderrSub = process.stderr
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(_output.write);
    process.exitCode.then((_) => _closed = true);
  }

  bool get isAlive => !_closed;

  /// Send a line of input, as if typed into the terminal and followed by
  /// Enter.
  void sendInput(String text) {
    if (_closed) {
      throw StateError('Terminal session $id has already closed.');
    }
    process.stdin.writeln(text);
  }

  /// Output produced since the last call to [readNewOutput] (or since the
  /// session started, on the first call). Consuming semantics — polling
  /// twice in a row without new output in between returns an empty string
  /// the second time, not a repeat.
  String readNewOutput() {
    final all = _output.toString();
    final fresh = all.substring(_readOffset);
    _readOffset = all.length;
    return fresh;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    process.kill();
  }
}

class WslTerminalManager {
  final WSLApi wslApi;
  final Map<String, WslTerminalSession> _sessions = {};
  int _nextId = 1;

  WslTerminalManager({WSLApi? wslApi}) : wslApi = wslApi ?? WSLApi();

  List<WslTerminalSession> get sessions => _sessions.values.toList();

  WslTerminalSession? session(String id) => _sessions[id];

  Future<WslTerminalSession> startSession(String distribution,
      {String? user}) async {
    final process = await wslApi.startShell(distribution, user: user);
    final id = 'term-${_nextId++}';
    final session = WslTerminalSession(
      id: id,
      distribution: distribution,
      user: user ?? 'root',
      process: process,
    );
    _sessions[id] = session;
    return session;
  }

  Future<void> closeSession(String id) async {
    final session = _sessions.remove(id);
    await session?.close();
  }

  /// Close every open session — call when the MCP server itself stops, so
  /// disabling the server doesn't leave orphaned WSL shell processes behind.
  Future<void> closeAll() async {
    final all = _sessions.values.toList();
    _sessions.clear();
    for (final session in all) {
      await session.close();
    }
  }
}
