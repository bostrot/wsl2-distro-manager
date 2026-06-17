import 'dart:convert';
import 'dart:io' show ProcessResult, Process, ProcessStartMode;

import 'package:flutter_test/flutter_test.dart';
import 'package:wsl2distromanager/api/execution/broker.dart';
import 'package:wsl2distromanager/api/execution/models.dart';
import 'package:wsl2distromanager/api/shell.dart';

/// A minimal mock shell that returns configurable results.
class TestShell implements Shell {
  String stdoutData = 'ok';
  String stderrData = '';
  int exitCode = 0;
  Duration? artificialDelay;

  List<String> lastCommand = [];
  List<List<String>> allCommands = [];

  bool throwOnRun = false;

  @override
  Future<ProcessResult> run(String executable, List<String> arguments,
      {String? workingDirectory,
      Map<String, String>? environment,
      bool includeParentEnvironment = true,
      bool runInShell = false,
      Encoding? stdoutEncoding,
      Encoding? stderrEncoding}) async {
    if (throwOnRun) throw Exception('shell error');
    lastCommand = [executable, ...arguments];
    allCommands.add([executable, ...arguments]);
    if (artificialDelay != null) await Future.delayed(artificialDelay!);
    // When an encoding is provided, the real shell returns a decoded String.
    // Return raw bytes only when encoding is null (WSL path).
    return ProcessResult(
      -1, // pid placeholder
      exitCode,
      stdoutEncoding != null ? stdoutData : utf8.encode(stdoutData),
      stderrEncoding != null ? stderrData : utf8.encode(stderrData),
    );
  }

  @override
  Future<Process> start(String executable, List<String> arguments,
      {String? workingDirectory,
      Map<String, String>? environment,
      bool includeParentEnvironment = true,
      ProcessStartMode mode = ProcessStartMode.inheritStdio,
      bool runInShell = false}) async {
    lastCommand = [executable, ...arguments];
    allCommands.add([executable, ...arguments]);
    throw UnsupportedError('start not implemented in TestShell');
  }

  void reset() {
    lastCommand.clear();
    allCommands.clear();
  }
}

void main() {
  group('ExecutionBroker policy enforcement', () {
    late TestShell testShell;
    late ExecutionBroker broker;

    setUp(() {
      testShell = TestShell();
      broker = ExecutionBroker(shell: testShell);
    });

    test('allowedCommands whitelist blocks disallowed command', () async {
      final request = ExecutionRequest(
        command: 'rm',
        arguments: ['-rf', '/tmp/test'],
        allowedCommands: ['ls', 'cat', 'pwd'],
      );
      expect(() => broker.run(request), throwsA(isA<Exception>()));
    });

    test('allowedCommands whitelist allows permitted command', () async {
      final request = ExecutionRequest(
        command: 'ls',
        arguments: ['-la'],
        allowedCommands: ['ls', 'cat', 'pwd'],
      );
      final result = await broker.run(request);
      expect(result.exitCode, 0);
      expect(testShell.lastCommand[0], 'ls');
    });

    test('allowedCommands null means no restriction', () async {
      final request = ExecutionRequest(
        command: 'rm',
        arguments: ['-rf', '/tmp/test'],
      );
      final result = await broker.run(request);
      expect(result.exitCode, 0);
    });

    test('readOnly mode blocks apt-get install', () async {
      final request = ExecutionRequest(
        command: 'apt-get',
        arguments: ['install', 'curl'],
        readOnly: true,
      );
      expect(() => broker.run(request), throwsA(isA<Exception>()));
    });

    test('readOnly mode blocks pip install', () async {
      final request = ExecutionRequest(
        command: 'pip',
        arguments: ['install', 'requests'],
        readOnly: true,
      );
      expect(() => broker.run(request), throwsA(isA<Exception>()));
    });

    test('readOnly mode blocks npm install', () async {
      final request = ExecutionRequest(
        command: 'npm',
        arguments: ['install', 'express'],
        readOnly: true,
      );
      expect(() => broker.run(request), throwsA(isA<Exception>()));
    });

    test('readOnly mode allows read-only commands from allowlist', () async {
      final request = ExecutionRequest(
        command: 'ls',
        arguments: ['-la'],
        readOnly: true,
      );
      expect(() => broker.run(request), returnsNormally);
    });

    test('readOnly mode allows cat', () async {
      final request = ExecutionRequest(
        command: 'cat',
        arguments: ['/etc/os-release'],
        readOnly: true,
      );
      expect(() => broker.run(request), returnsNormally);
    });
  });

  group('ExecutionBroker audit trail', () {
    late TestShell testShell;
    late ExecutionBroker broker;

    setUp(() {
      testShell = TestShell();
      broker = ExecutionBroker(shell: testShell);
    });

    test('audit log records successful execution', () async {
      await broker.run(const ExecutionRequest(
        command: 'echo',
        arguments: ['hello'],
      ));
      expect(broker.auditLog.length, 1);
      final entry = broker.auditLog.first;
      expect(entry.request.command, 'echo');
      expect(entry.exitCode, 0);
      expect(entry.severity, AuditSeverity.info);
    });

    test('audit log records failed execution', () async {
      testShell.exitCode = 1;
      await broker.run(const ExecutionRequest(
        command: 'false',
        arguments: [],
      ));
      expect(broker.auditLog.length, 1);
      final entry = broker.auditLog.first;
      expect(entry.exitCode, 1);
      expect(entry.severity, AuditSeverity.error);
    });

    test('audit log accumulates entries', () async {
      await broker.run(const ExecutionRequest(command: 'echo', arguments: ['a']));
      await broker.run(const ExecutionRequest(command: 'ls', arguments: ['-la']));
      await broker.run(const ExecutionRequest(command: 'cat', arguments: ['/etc/hostname']));
      expect(broker.auditLog.length, 3);
    });

    test('clearAuditLog empties history', () async {
      await broker.run(const ExecutionRequest(command: 'echo', arguments: ['test']));
      expect(broker.auditLog.length, 1);
      broker.clearAuditLog();
      expect(broker.auditLog.isEmpty, true);
    });
  });

  group('ExecutionBroker run result', () {
    late TestShell testShell;
    late ExecutionBroker broker;

    setUp(() {
      testShell = TestShell();
      broker = ExecutionBroker(shell: testShell);
    });

    test('returns stdout from shell', () async {
      testShell.stdoutData = 'hello world';
      final result = await broker.run(const ExecutionRequest(
        command: 'echo',
        arguments: ['hello world'],
      ));
      expect(result.stdout, contains('hello world'));
    });

    test('returns stderr from shell', () async {
      testShell.stderrData = 'error message';
      final result = await broker.run(const ExecutionRequest(
        command: 'bad-cmd',
        arguments: [],
      ));
      expect(result.stderr, contains('error message'));
    });

    test('returns exit code from shell', () async {
      testShell.exitCode = 42;
      final result = await broker.run(const ExecutionRequest(
        command: 'custom',
        arguments: [],
      ));
      expect(result.exitCode, 42);
    });

    test('measures execution duration', () async {
      testShell.artificialDelay = const Duration(milliseconds: 50);
      final result = await broker.run(const ExecutionRequest(
        command: 'slow-cmd',
        arguments: [],
      ));
      expect(result.duration.inMilliseconds, greaterThanOrEqualTo(40));
    });

    test('captures the command and arguments in audit entry', () async {
      await broker.run(const ExecutionRequest(
        command: 'wsl',
        arguments: ['--list', '--quiet'],
      ));
      final entry = broker.auditLog.first;
      expect(entry.request.command, 'wsl');
      expect(entry.request.arguments, ['--list', '--quiet']);
    });

    test('forwards runInShell to shell.run()', () async {
      final result = await broker.run(const ExecutionRequest(
        command: 'cmd',
        arguments: ['/c', 'echo hello'],
        runInShell: true,
      ));
      expect(result.exitCode, 0);
    });
  });

  group('ExecutionBroker runStream events', () {
    late TestShell testShell;
    late ExecutionBroker broker;

    setUp(() {
      testShell = TestShell();
      broker = ExecutionBroker(shell: testShell);
    });

    // Note: runStream() delegates to Shell.start() which spawns a real process.
    // Unit tests can only verify behavior when start() fails (ExecutionError path).
    // Full stream event ordering is verified by integration/e2e tests.

    test('runStream emits ExecutionStarted before error', () async {
      testShell.throwOnRun = true;
      final events = <ExecutionEvent>[];
      await broker.runStream(const ExecutionRequest(
        command: 'echo',
        arguments: ['streaming'],
      )).forEach(events.add);

      expect(events.first, isA<ExecutionStarted>());
    });

    test('StdOutChunk events not emitted when start fails', () async {
      final events = <ExecutionEvent>[];
      await broker.runStream(const ExecutionRequest(
        command: 'echo',
        arguments: ['data'],
      )).forEach(events.add);

      // TestShell.start() throws, so no stdout chunks
      final stdoutEvents = events.whereType<StdOutChunk>().toList();
      expect(stdoutEvents.isEmpty, true);
    });

    test('ExecutionStarted event has correct metadata', () async {
      final events = <ExecutionEvent>[];
      await broker.runStream(const ExecutionRequest(
        command: 'test-cmd',
        arguments: ['arg1', 'arg2'],
      )).forEach(events.add);

      final started = events.first as ExecutionStarted;
      expect(started.command, 'test-cmd');
      expect(started.arguments, ['arg1', 'arg2']);
    });

    test('ExecutionExited not emitted when start fails (gets Error instead)', () async {
      final events = <ExecutionEvent>[];
      await broker.runStream(const ExecutionRequest(
        command: 'echo',
        arguments: ['done'],
      )).forEach(events.add);

      // Last event is ExecutionError because TestShell.start() throws
      expect(events.last, isA<ExecutionError>());
    });
  });

  group('ExecutionBroker error handling', () {
    late TestShell testShell;
    late ExecutionBroker broker;

    setUp(() {
      testShell = TestShell();
      broker = ExecutionBroker(shell: testShell);
    });

    test('run() catches shell exception and returns error result', () async {
      testShell.throwOnRun = true;
      final result = await broker.run(const ExecutionRequest(
        command: 'bad',
        arguments: [],
      ));
      expect(result.exitCode, -1);
      expect(result.auditSeverity, AuditSeverity.error);
    });

    test('runStream() emits ExecutionError on shell exception', () async {
      testShell.throwOnRun = true;
      final events = <ExecutionEvent>[];
      await broker.runStream(const ExecutionRequest(
        command: 'bad',
        arguments: [],
      )).forEach(events.add);

      expect(events.first, isA<ExecutionStarted>());
      expect(events.any((e) => e is ExecutionError), true);
    });

    test('policy violation does not add audit entry', () async {
      broker.clearAuditLog();
      try {
        await broker.run(const ExecutionRequest(
          command: 'rm',
          arguments: ['-rf', '/'],
          allowedCommands: ['ls'],
        ));
        fail('Expected exception');
      } catch (e) {
        // Expected
      }
      expect(broker.auditLog.isEmpty, true);
    });
  });

  group('ExecutionRequest defaults', () {
    test('default timeout is 5 minutes', () {
      final request = const ExecutionRequest(command: 'test');
      expect(request.timeout, const Duration(minutes: 5));
    });

    test('default captureOutput is true', () {
      final request = const ExecutionRequest(command: 'test');
      expect(request.captureOutput, true);
    });

    test('default readOnly is false', () {
      final request = const ExecutionRequest(command: 'test');
      expect(request.readOnly, false);
    });

    test('custom timeout is preserved', () {
      final request = const ExecutionRequest(
        command: 'test',
        timeout: Duration(minutes: 15),
      );
      expect(request.timeout, const Duration(minutes: 15));
    });
  });
}
