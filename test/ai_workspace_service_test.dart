import 'dart:async';
import 'dart:convert';
import 'dart:io' show ProcessResult, Process, ProcessStartMode;

import 'package:flutter_test/flutter_test.dart';
import 'package:wsl2distromanager/api/ai_workspace/service.dart';
import 'package:wsl2distromanager/api/execution/broker.dart';
import 'package:wsl2distromanager/api/shell.dart';

/// A minimal mock shell that returns configurable results.
class TestShell implements Shell {
  String stdoutData = '';
  String stderrData = '';
  int exitCode = 0;
  Duration? artificialDelay;
  bool throwOnRun = false;

  List<String> lastCommand = [];
  List<List<String>> allCommands = [];

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
    return ProcessResult(
      -1, // pid placeholder
      exitCode,
      utf8.encode(stdoutData),
      utf8.encode(stderrData),
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
    stdoutData = '';
    stderrData = '';
    exitCode = 0;
    lastCommand.clear();
    allCommands.clear();
    artificialDelay = null;
    throwOnRun = false;
  }
}

void main() {
  group('AiWorkspaceService', () {
    late TestShell testShell;
    late ExecutionBroker broker;
    late AiWorkspaceService service;

    setUp(() {
      testShell = TestShell();
      broker = ExecutionBroker(shell: testShell);
      service = AiWorkspaceService(broker: broker);
    });

    tearDown(() {
      testShell.reset();
    });

    group('ensureDistro', () {
      test('marks distro ready when it already exists', () async {
        // wsl --list --quiet returns the ai-workspace distro name
        testShell.stdoutData = 'Alpine\nai-workspace\nUbuntu';
        await service.ensureDistro();

        expect(testShell.lastCommand, ['wsl', '--list', '--quiet']);
      });

      test('attempts to install Ubuntu when distro missing', () async {
        // wsl --list --quiet returns no ai-workspace
        testShell.stdoutData = 'Alpine\nUbuntu';
        await service.ensureDistro();

        // Should have tried to install on the second wsl --install call
        expect(
          testShell.allCommands.any((cmd) => cmd.contains('--install')),
          true,
          reason: 'Should attempt to install Ubuntu',
        );
      });
    });

    group('init', () {
      test('initializes all tool states and probes status', () async {
        // Distro check succeeds immediately (first call)
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        expect(service.toolStates.length, AiWorkspaceTool.values.length);
        for (final tool in AiWorkspaceTool.values) {
          expect(service.getState(tool), isNotNull);
        }
      });
    });

    group('install', () {
      test('installs hermes agent successfully', () async {
        // First call: ensureDistro list check. Tool states init via init().
        testShell.stdoutData = 'ai-workspace';
        await service.init(); // initializes tool states + consumes distro check

        // Now install should work — the wsl command for install goes through broker
        testShell.exitCode = 0;
        final result = await service.install(AiWorkspaceTool.hermesAgent);

        expect(result, true);
        expect(
          service.getState(AiWorkspaceTool.hermesAgent)?.status,
          ToolStatus.stopped,
        );
      });

      test('returns false and sets error on install failure', () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        testShell.exitCode = 1;
        testShell.stderrData = 'curl failed';

        final result = await service.install(AiWorkspaceTool.openClaw);

        expect(result, false);
        expect(
          service.getState(AiWorkspaceTool.openClaw)?.status,
          ToolStatus.error,
        );
        expect(
          service.getState(AiWorkspaceTool.openClaw)?.errorMessage,
          contains('curl failed'),
        );
      });
    });

    group('start/stop', () {
      test('starts a stopped tool', () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        // Pre-set tool as installed/stopped
        final state = service.getState(AiWorkspaceTool.hermesAgent)!;
        state.status = ToolStatus.stopped;

        testShell.exitCode = 0;
        final result = await service.start(AiWorkspaceTool.hermesAgent);

        expect(result, true);
        expect(state.status, ToolStatus.running);
        expect(state.lastStarted, isNotNull);
      });

      test('stops a running tool', () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        final state = service.getState(AiWorkspaceTool.hermesAgent)!;
        state.status = ToolStatus.running;

        testShell.exitCode = 0;
        final result = await service.stop(AiWorkspaceTool.hermesAgent);

        expect(result, true);
        expect(state.status, ToolStatus.stopped);
        expect(state.lastStopped, isNotNull);
      });

      test('cannot start uninstalled tool', () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        // Force tool to notInstalled since init() probes status (mock returns "running")
        final state = service.getState(AiWorkspaceTool.hermesAgent)!;
        state.status = ToolStatus.notInstalled;

        final result = await service.start(AiWorkspaceTool.hermesAgent);

        expect(result, false);
      });
    });

    group('uninstall', () {
      test('uninstalls a filesystem-based tool', () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        final state = service.getState(AiWorkspaceTool.hermesAgent)!;
        state.status = ToolStatus.stopped;

        testShell.exitCode = 0;
        final result = await service.uninstall(AiWorkspaceTool.hermesAgent);

        expect(result, true);
        expect(state.status, ToolStatus.notInstalled);
        expect(state.installPath, isNull);
      });

      test('stops running tool before uninstalling', () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        final state = service.getState(AiWorkspaceTool.hermesAgent)!;
        state.status = ToolStatus.running;

        testShell.exitCode = 0; // stop succeeds, then uninstall succeeds
        final result = await service.uninstall(AiWorkspaceTool.hermesAgent);

        expect(result, true);
        expect(state.status, ToolStatus.notInstalled);
      });
    });

    group('refreshStatus', () {
      test('detects running status', () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        // Status check returns "running"
        testShell.stdoutData = 'running';
        await service.refreshStatus(AiWorkspaceTool.hermesAgent);

        expect(
          service.getState(AiWorkspaceTool.hermesAgent)?.status,
          ToolStatus.running,
        );
      });

      test('detects stopped status', () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        // Status check returns "stopped"
        testShell.stdoutData = 'stopped';
        await service.refreshStatus(AiWorkspaceTool.openClaw);

        expect(
          service.getState(AiWorkspaceTool.openClaw)?.status,
          ToolStatus.stopped,
        );
      });

      test('handles error gracefully', () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        // Status check fails with stderr about distro not found
        testShell.exitCode = 1;
        testShell.stderrData = 'distribution ai-workspace could not be found';
        await service.refreshStatus(AiWorkspaceTool.openWebUi);

        expect(
          service.getState(AiWorkspaceTool.openWebUi)?.status,
          ToolStatus.notInstalled,
        );
      });
    });

    group('getUrl', () {
      test('returns URL for running tool', () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        final state = service.getState(AiWorkspaceTool.hermesAgent)!;
        state.status = ToolStatus.running;

        expect(
          service.getUrl(AiWorkspaceTool.hermesAgent),
          'http://localhost:8081',
        );
      });

      test('returns null for non-running tool', () async {
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        final state = service.getState(AiWorkspaceTool.openClaw)!;
        state.status = ToolStatus.stopped;

        expect(service.getUrl(AiWorkspaceTool.openClaw), isNull);
      });
    });

    group('wsl command routing', () {
      test('all commands use wsl with -d ai-workspace flag', () async {
        // Distro check + init
        testShell.stdoutData = 'ai-workspace';
        await service.init();

        // Install command should route through WSL
        await service.install(AiWorkspaceTool.hermesAgent);

        expect(testShell.lastCommand[0], 'wsl');
        expect(
          testShell.allCommands.any(
            (cmd) => cmd.contains('-d') && cmd.contains(kAiWorkspaceDistro),
          ),
          true,
        );
      });
    });
  });
}
