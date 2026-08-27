// Central execution dispatcher wrapping the existing [Shell] interface.
// Provides policy enforcement, audit logging, and event streaming on top of
// raw process execution. Consumers should route command requests through this
// broker instead of spawning processes directly.
import 'dart:async';
import 'dart:convert' show Utf8Decoder;
import 'dart:io' show Process, ProcessSignal, systemEncoding;

import '../shell.dart';
import 'models.dart';

/// Default list of commands considered safe for read-only mode.
const List<String> _defaultReadOnlyAllowList = [
  'cat', 'ls', 'pwd', 'echo', 'id', 'whoami',
  'uname', 'hostname', 'df', 'du', 'free',
  'wsl', 'docker',
];

/// Central execution broker.
class ExecutionBroker {
  final Shell _shell;
  final List<AuditEntry> _auditLog = [];

  /// Create a broker backed by the given [Shell] implementation.
  ExecutionBroker({required Shell shell}) : _shell = shell;

  /// Append-only audit log (most recent entries at end).
  List<AuditEntry> get auditLog => List.unmodifiable(_auditLog);

  /// Clear audit history.
  void clearAuditLog() => _auditLog.clear();

  // -----------------------------------------------------------------------
  // Output decoding
  // -----------------------------------------------------------------------

  /// Decode WSL process output (UTF-16LE with null-byte separators) to text.
  ///
  /// WSL on Windows outputs UTF-16LE, so every ASCII char is followed by a
  /// null byte. This decoder strips the null bytes and decodes as UTF-8,
  /// matching [WSLApi.utf8Convert].
  static String decodeWslOutput(dynamic data) {
    if (data == null || (data is List && data.isEmpty)) return '';
    if (data is String) return _stripControlChars(data);
    // Raw bytes from ProcessResult with stdoutEncoding: null.
    final bytes = data as List<int>;
    final decoded = const Utf8Decoder(allowMalformed: true).convert(bytes);
    return _stripControlChars(decoded);
  }

  /// Strip control characters (including the null bytes from UTF-16LE output)
  /// while preserving common whitespace.
  static String _stripControlChars(String text) {
    return text.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');
  }

  /// Returns true when the command is a WSL invocation that produces UTF-16LE output.
  static bool _isWslCommand(String command) {
    return command.toLowerCase() == 'wsl' || command.toLowerCase().endsWith('wsl.exe');
  }

  /// Decode with the platform encoding, mirroring the `systemEncoding` that
  /// [run] used to hand to `Process.run` for non-WSL commands. Falls back to a
  /// lenient UTF-8 decode so one bad byte cannot fail the whole call.
  static String _decodeSystem(List<int> bytes) {
    if (bytes.isEmpty) return '';
    try {
      return systemEncoding.decode(bytes);
    } on FormatException {
      return const Utf8Decoder(allowMalformed: true).convert(bytes);
    }
  }

  // -----------------------------------------------------------------------
  // Process lifetime
  // -----------------------------------------------------------------------

  /// Terminate a child that outlived its timeout, escalating to SIGKILL when
  /// it does not go away on its own.
  static Future<void> _terminate(Process process) async {
    try {
      process.kill();
      await process.exitCode.timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          process.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
    } catch (_) {
      // Already reaped, or the platform refused the signal — nothing to undo.
    }
  }

  // -----------------------------------------------------------------------
  // Policy enforcement
  // -----------------------------------------------------------------------

  void _checkPolicy(ExecutionRequest request) {
    // Allowed-commands whitelist
    if (request.allowedCommands != null && request.allowedCommands!.isNotEmpty) {
      if (!request.allowedCommands!.contains(request.command)) {
        throw Exception(
          'Command "${request.command}" is not in the allowed list',
        );
      }
    }

    // Read-only mode blocks known-writable commands
    if (request.readOnly && !_defaultReadOnlyAllowList.contains(request.command)) {
      final lower = request.command.toLowerCase();
      if (lower.contains('install') ||
          lower.contains('remove') ||
          lower.contains('apt') ||
          lower.contains('pip') ||
          lower.contains('npm')) {
        throw Exception(
          'Command "${request.command}" is blocked in read-only mode',
        );
      }
    }
  }

  // -----------------------------------------------------------------------
  // Core execution methods
  // -----------------------------------------------------------------------

  /// Execute a command synchronously and capture output.
  Future<ExecutionResult> run(ExecutionRequest request) async {
    _checkPolicy(request);

    final entry = AuditEntry(
      timestamp: DateTime.now(),
      request: request,
    );
    _auditLog.add(entry);

    final stopwatch = Stopwatch()..start();

    try {
      final isWsl = _isWslCommand(request.command);

      // Deliberately `start` and not `run`: `Process.run` hands back no handle,
      // so a timeout could only abandon the child. With `list.dart` re-polling
      // every 5s that leaked hundreds of orphaned wsl.exe processes.
      final process = await _shell.start(
        request.command,
        request.arguments,
        workingDirectory: request.workingDirectory,
        environment: request.environment,
        runInShell: request.runInShell,
      );

      final stdoutBytes = <int>[];
      final stderrBytes = <int>[];
      final stdoutDone = Completer<void>();
      final stderrDone = Completer<void>();

      StreamSubscription<List<int>> drain(
        Stream<List<int>> stream,
        List<int> sink,
        Completer<void> done,
      ) {
        return stream.listen(
          sink.addAll,
          onDone: () {
            if (!done.isCompleted) done.complete();
          },
          onError: (Object e) {
            if (!done.isCompleted) done.completeError(e);
          },
        );
      }

      final stdoutSub = drain(process.stdout, stdoutBytes, stdoutDone);
      final stderrSub = drain(process.stderr, stderrBytes, stderrDone);

      final completion = () async {
        final code = await process.exitCode;
        await Future.wait([stdoutDone.future, stderrDone.future]);
        return code;
      }();

      final int exitCode;
      try {
        exitCode = await completion.timeout(request.timeout);
      } catch (e) {
        // Reap the child before surfacing anything, otherwise it outlives us.
        await _terminate(process);
        await stdoutSub.cancel();
        await stderrSub.cancel();
        if (e is TimeoutException) {
          throw TimeoutException(
            'Command timed out after ${request.timeout.inSeconds}s: '
            '${request.command} ${request.arguments.join(' ')}',
            request.timeout,
          );
        }
        rethrow;
      }

      stopwatch.stop();

      final severity = exitCode == 0 ? AuditSeverity.info : AuditSeverity.error;

      // Update audit log entry.
      _auditLog.removeLast();
      _auditLog.add(AuditEntry(
        timestamp: entry.timestamp,
        request: request,
        exitCode: exitCode,
        duration: stopwatch.elapsed,
        severity: severity,
      ));

      // WSL emits UTF-16LE, so its bytes go to the manual decoder untouched;
      // everything else decodes with the system encoding first. Same split
      // `stdoutEncoding: isWsl ? null : systemEncoding` used to express.
      String decode(List<int> bytes) =>
          decodeWslOutput(isWsl ? bytes : _decodeSystem(bytes));

      return ExecutionResult(
        exitCode: exitCode,
        stdout: decode(stdoutBytes),
        stderr: decode(stderrBytes),
        duration: stopwatch.elapsed,
        auditSeverity: severity,
      );
    } catch (e) {
      stopwatch.stop();

      _auditLog.removeLast();
      _auditLog.add(AuditEntry(
        timestamp: entry.timestamp,
        request: request,
        duration: stopwatch.elapsed,
        severity: AuditSeverity.error,
        errorMessage: e.toString(),
      ));

      return ExecutionResult(
        exitCode: -1,
        stderr: '$e',
        duration: stopwatch.elapsed,
        error: e,
        auditSeverity: AuditSeverity.error,
      );
    }
  }

  /// Starts a long-running process and hands back the handle.
  ///
  /// No timeout and no output capture: the caller owns the lifetime and must
  /// `kill()` it. Used for session keep-alives, where the point is that the
  /// process outlives any single command.
  Future<Process> startPersistent(ExecutionRequest request) {
    _checkPolicy(request);
    return _shell.start(
      request.command,
      request.arguments,
      workingDirectory: request.workingDirectory,
      environment: request.environment,
      runInShell: request.runInShell,
    );
  }

  /// Execute a command and stream events as it runs.
  Stream<ExecutionEvent> runStream(ExecutionRequest request) {
    _checkPolicy(request);

    final entry = AuditEntry(
      timestamp: DateTime.now(),
      request: request,
    );
    _auditLog.add(entry);

    final stopwatch = Stopwatch()..start();

    // Use a controller to manually manage the stream.
    final controller = StreamController<ExecutionEvent>();

    Future(() async {
      try {
        controller.add(ExecutionStarted(
          command: request.command,
          arguments: request.arguments,
          timestamp: DateTime.now(),
        ));

        // Delegate to Shell.start for async streaming.
        final process = await _shell.start(
          request.command,
          request.arguments,
          workingDirectory: request.workingDirectory,
          environment: request.environment,
          runInShell: request.runInShell,
        );

        if (request.captureOutput) {
          final isWsl = _isWslCommand(request.command);

          // Listen to stdout/stderr and forward as events.
          final stdoutSub = process.stdout.listen((data) {
            controller.add(StdOutChunk(
              isWsl ? decodeWslOutput(data) : String.fromCharCodes(data),
            ));
          });

          final stderrSub = process.stderr.listen((data) {
            controller.add(StdErrChunk(
              isWsl ? decodeWslOutput(data) : String.fromCharCodes(data),
            ));
          });

          final exitCode = await process.exitCode;
          stopwatch.stop();

          // Wait for streams to close before yielding exit event.
          await stdoutSub.cancel();
          await stderrSub.cancel();

          final severity = exitCode == 0 ? AuditSeverity.info : AuditSeverity.error;

          controller.add(ExecutionExited(
            exitCode: exitCode,
            duration: stopwatch.elapsed,
            timestamp: DateTime.now(),
          ));

          // Update audit log.
          _auditLog.removeLast();
          _auditLog.add(AuditEntry(
            timestamp: entry.timestamp,
            request: request,
            exitCode: exitCode,
            duration: stopwatch.elapsed,
            severity: severity,
          ));
        } else {
          // Non-capturing mode — just wait for exit.
          final exitCode = await process.exitCode;
          stopwatch.stop();

          controller.add(ExecutionExited(
            exitCode: exitCode,
            duration: stopwatch.elapsed,
            timestamp: DateTime.now(),
          ));

          _auditLog.removeLast();
          _auditLog.add(AuditEntry(
            timestamp: entry.timestamp,
            request: request,
            exitCode: exitCode,
            duration: stopwatch.elapsed,
            severity: exitCode == 0 ? AuditSeverity.info : AuditSeverity.error,
          ));
        }

        await controller.close();
      } catch (e) {
        stopwatch.stop();

        controller.add(ExecutionError(e));

        _auditLog.removeLast();
        _auditLog.add(AuditEntry(
          timestamp: entry.timestamp,
          request: request,
          duration: stopwatch.elapsed,
          severity: AuditSeverity.error,
          errorMessage: e.toString(),
        ));

        await controller.close();
      }
    });

    return controller.stream;
  }
}
