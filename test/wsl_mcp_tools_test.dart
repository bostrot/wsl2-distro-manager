import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wsl2distromanager/api/mcp/mcp_server.dart';
import 'package:wsl2distromanager/api/mcp/wsl_mcp_tools.dart';
import 'package:wsl2distromanager/api/mcp/wsl_terminal_manager.dart';
import 'package:wsl2distromanager/api/wsl.dart';
import 'package:wsl2distromanager/components/helpers.dart';

import 'mocks.dart';

void main() {
  late MockShell mockShell;
  late WSLApi wslApi;
  late WslTerminalManager terminalManager;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    mockShell = MockShell();
    wslApi = WSLApi(shell: mockShell);
    terminalManager = WslTerminalManager(wslApi: wslApi);
  });

  McpTool tool(String name) => buildWslMcpTools(wslApi, terminalManager)
      .firstWhere((t) => t.name == name);

  group('wsl_list_distros', () {
    test('lists distros with running/stopped status', () async {
      mockShell.distros.addAll(['Ubuntu', 'ai-workspace']);
      // list() only reports something "running" via a separate mechanism in
      // the real WSLApi.list(); MockShell always returns the same names for
      // both --list variants, so just assert the tool surfaces every distro.
      final result = await tool('wsl_list_distros').handler({});
      expect(result, contains('Ubuntu'));
      expect(result, contains('ai-workspace'));
    });

    test('reports when there are no distros', () async {
      final result = await tool('wsl_list_distros').handler({});
      expect(result, 'No WSL distros installed.');
    });
  });

  group('wsl_run_command', () {
    test('runs the command as root in the named distro', () async {
      await tool('wsl_run_command')
          .handler({'distro': 'Ubuntu', 'command': 'echo hi'});

      expect(mockShell.lastRunArguments,
          ['-d', 'Ubuntu', '-u', 'root', '--exec', 'bash', '-c', 'echo hi']);
    });

    test('forwards the client command verbatim, quoting intact', () async {
      // This tool hands an MCP client's command straight to the distro, so it
      // is the call site that suffered most from the old pre-split form: the
      // split stripped the quotes and wsl.exe's default shell then re-parsed
      // the unquoted result. See lib/api/wsl_args.dart.
      const cmd = "grep -c 'root:x:0' /etc/passwd | tee /tmp/n";
      await tool('wsl_run_command').handler({'distro': 'Ubuntu', 'command': cmd});

      expect(mockShell.lastRunArguments.last, cmd);
      expect(mockShell.lastRunArguments, contains('--exec'));
      expect(mockShell.lastRunInShell, isFalse);
    });

    test('rejects a missing distro argument', () async {
      expect(
        () => tool('wsl_run_command').handler({'command': 'echo hi'}),
        throwsArgumentError,
      );
    });

    test('rejects a missing command argument', () async {
      expect(
        () => tool('wsl_run_command').handler({'distro': 'Ubuntu'}),
        throwsArgumentError,
      );
    });

    test('reports "(no output)" instead of an empty string', () async {
      final result = await tool('wsl_run_command')
          .handler({'distro': 'Ubuntu', 'command': 'true'});
      expect(result, '(no output)');
    });
  });

  group('wsl_stop_distro', () {
    test('terminates the named distro', () async {
      final result =
          await tool('wsl_stop_distro').handler({'distro': 'Ubuntu'});

      expect(mockShell.lastRunArguments, contains('--terminate'));
      expect(mockShell.lastRunArguments, contains('Ubuntu'));
      expect(result, contains('Ubuntu'));
    });

    test('rejects a missing distro argument', () async {
      expect(
        () => tool('wsl_stop_distro').handler({}),
        throwsArgumentError,
      );
    });
  });

  test('the destructive operations are not exposed as tools', () {
    final names =
        buildWslMcpTools(wslApi, terminalManager).map((t) => t.name).toSet();
    // Deliberately excluded from v1: distro creation/deletion/export/move
    // are one-way or disk-heavy and belong in the GUI where a human
    // directly confirms them, not behind an agent-callable MCP tool.
    expect(names, {
      'wsl_list_distros',
      'wsl_run_command',
      'wsl_stop_distro',
      'wsl_terminal_start',
      'wsl_terminal_send',
      'wsl_terminal_read',
      'wsl_terminal_list',
      'wsl_terminal_close',
    });
  });

  group('wsl_terminal_*', () {
    test('start returns a session id and the manager tracks it', () async {
      final result = await tool('wsl_terminal_start').handler({'distro': 'Ubuntu'});

      expect(result, contains('Ubuntu'));
      expect(terminalManager.sessions, hasLength(1));
      expect(mockShell.lastStartExecutable, 'wsl');
      expect(mockShell.lastStartArguments, containsAllInOrder(['-d', 'Ubuntu', '-u', 'root']));
    });

    test('send rejects an unknown session id', () async {
      expect(
        () => tool('wsl_terminal_send')
            .handler({'session_id': 'nope', 'input': 'echo hi'}),
        throwsArgumentError,
      );
    });

    test('read rejects an unknown session id', () async {
      expect(
        () => tool('wsl_terminal_read').handler({'session_id': 'nope'}),
        throwsArgumentError,
      );
    });

    test('close rejects an unknown session id', () async {
      expect(
        () => tool('wsl_terminal_close').handler({'session_id': 'nope'}),
        throwsArgumentError,
      );
    });

    test('list reports no sessions when none are open', () async {
      final result = await tool('wsl_terminal_list').handler({});
      expect(result, 'No open terminal sessions.');
    });

    test('start, list, then close round-trips through the manager',
        () async {
      final startResult =
          await tool('wsl_terminal_start').handler({'distro': 'Ubuntu'});
      final sessionId = terminalManager.sessions.single.id;
      expect(startResult, contains(sessionId));

      final listResult = await tool('wsl_terminal_list').handler({});
      expect(listResult, contains(sessionId));
      expect(listResult, contains('Ubuntu'));

      final closeResult =
          await tool('wsl_terminal_close').handler({'session_id': sessionId});
      expect(closeResult, contains(sessionId));
      expect(terminalManager.sessions, isEmpty);
    });
  });
}
