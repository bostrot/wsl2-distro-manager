// Central execution dispatcher wrapping the existing [Shell] interface.
// Provides policy enforcement, audit logging, and event streaming on top of
// raw process execution. Consumers should route command requests through this
// broker instead of spawning processes directly.
import 'dart:async';
import 'dart:convert' show Utf8Decoder;
import 'dart:io' show ProcessResult, systemEncoding;

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

      final ProcessResult result = await _shell.run(
        request.command,
        request.arguments,
        workingDirectory: request.workingDirectory,
        environment: request.environment,
        runInShell: request.runInShell,
        // WSL outputs UTF-16LE on Windows; get raw bytes and decode manually.
        stdoutEncoding: isWsl ? null : systemEncoding,
        stderrEncoding: isWsl ? null : systemEncoding,
      ).timeout(
        request.timeout,
        onTimeout: () => throw TimeoutException(
          'Command timed out after ${request.timeout.inSeconds}s: '
          '${request.command} ${request.arguments.join(' ')}',
          request.timeout,
        ),
      );

      stopwatch.stop();

      final severity = result.exitCode == 0
          ? AuditSeverity.info
          : AuditSeverity.error;

      // Update audit log entry.
      _auditLog.removeLast();
      _auditLog.add(AuditEntry(
        timestamp: entry.timestamp,
        request: request,
        exitCode: result.exitCode,
        duration: stopwatch.elapsed,
        severity: severity,
      ));

      return ExecutionResult(
        exitCode: result.exitCode,
        stdout: decodeWslOutput(result.stdout),
        stderr: decodeWslOutput(result.stderr),
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
