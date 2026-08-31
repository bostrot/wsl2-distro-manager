import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:wsl2distromanager/api/process_reaper.dart';

/// Shared SSH client options for remote WSL connections.
List<String> getSshClientOptions() {
  final tmpDir = Directory.systemTemp.path;
  final controlPath = p.join(tmpDir, 'wsl2dm_ssh_mux.sock');
  return <String>[
    '-o',
    'BatchMode=yes',
    '-o',
    'PasswordAuthentication=no',
    '-o',
    'KbdInteractiveAuthentication=no',
    '-o',
    'ControlMaster=auto',
    '-o',
    'ControlPersist=10m',
    '-o',
    'ControlPath=$controlPath',
    '-o',
    'ServerAliveInterval=30',
    '-o',
    'ServerAliveCountMax=3',
  ];
}

/// Interface for shell operations to allow mocking
abstract class Shell {
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    Encoding? stdoutEncoding = systemEncoding,
    Encoding? stderrEncoding = systemEncoding,
  });

  Future<Process> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    ProcessStartMode mode = ProcessStartMode.normal,
  });
}

/// Default implementation using dart:io Process
class ProcessShell implements Shell {
  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    Encoding? stdoutEncoding = systemEncoding,
    Encoding? stderrEncoding = systemEncoding,
  }) {
    return Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      includeParentEnvironment: includeParentEnvironment,
      runInShell: runInShell,
      stdoutEncoding: stdoutEncoding,
      stderrEncoding: stderrEncoding,
    );
  }

  @override
  Future<Process> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    ProcessStartMode mode = ProcessStartMode.normal,
  }) async {
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      includeParentEnvironment: includeParentEnvironment,
      runInShell: runInShell,
      mode: mode,
    );
    // Tie the child to the app job so a force-kill of the app takes it down
    // too — best-effort, never throws, no-op off Windows.
    ProcessReaper.instance.adopt(process.pid);
    return process;
  }
}
