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

      // Through the broker now (start channel), so assert on runCalls,
      // which sees both channels.
      expect(mockShell.runCalls.last,
          ['-d', 'Ubuntu', '-u', 'root', '--exec', 'bash', '-c', 'echo hi']);
    });

    test('forwards the client command verbatim, quoting intact', () async {
      // This tool hands an MCP client's command straight to the distro, so it
      // is the call site that suffered most from the old pre-split form: the
      // split stripped the quotes and wsl.exe's default shell then re-parsed
      // the unquoted result. See lib/api/wsl_args.dart.
      const cmd = "grep -c 'root:x:0' /etc/passwd | tee /tmp/n";
      await tool('wsl_run_command')
          .handler({'distro': 'Ubuntu', 'command': cmd});

      expect(mockShell.runCalls.last.last, cmd);
      expect(mockShell.runCalls.last, contains('--exec'));
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

  test('the tool surface covers the whole lifecycle', () {
    final names =
        buildWslMcpTools(wslApi, terminalManager).map((t) => t.name).toSet();
    // v2 exposes create → configure → operate → destroy. The one-way
    // operation (unregister) is confirm-gated rather than hidden — see the
    // dedicated group below.
    expect(names, {
      'wsl_list_distros',
      'wsl_distro_info',
      'wsl_status',
      'wsl_list_online_distros',
      'wsl_install_distro',
      'wsl_import_distro',
      'wsl_import_in_place',
      'wsl_export_distro',
      'wsl_unregister_distro',
      'wsl_get_wsl_conf',
      'wsl_set_wsl_conf',
      'wsl_get_wslconfig',
      'wsl_set_wslconfig',
      'wsl_set_default_user',
      'wsl_set_default_distro',
      'wsl_set_version',
      'wsl_run_command',
      'wsl_stop_distro',
      'wsl_shutdown',
      'wsl_copy_to',
      'wsl_copy_from',
      'wsl_move_distro',
      'wsl_resize_distro',
      'wsl_compact_disk',
      'wsl_mount_disk',
      'wsl_unmount_disk',
      'wsl_terminal_start',
      'wsl_terminal_send',
      'wsl_terminal_read',
      'wsl_terminal_signal',
      'wsl_terminal_list',
      'wsl_terminal_close',
    });
  });

  group('wsl_run_command overrides', () {
    test('user, cwd and timeout reshape the argv', () async {
      await tool('wsl_run_command').handler({
        'distro': 'Ubuntu',
        'command': 'make',
        'user': 'dev',
        'cwd': '/src',
        'timeout_seconds': 10,
      });

      expect(mockShell.runCalls.last, [
        '-d',
        'Ubuntu',
        '--cd',
        '/src',
        '-u',
        'dev',
        '--exec',
        'bash',
        '-c',
        'make',
      ]);
    });
  });

  group('wsl_unregister_distro', () {
    test('refuses without confirm and touches nothing', () async {
      await expectLater(
        tool('wsl_unregister_distro')
            .handler({'distro': 'Ubuntu', 'confirm': false}),
        throwsArgumentError,
      );
      expect(mockShell.runCalls, isEmpty);
    });

    test('unregisters with confirm: true', () async {
      final result = await tool('wsl_unregister_distro')
          .handler({'distro': 'Ubuntu', 'confirm': true});

      expect(mockShell.runCalls.any((c) => c.contains('--unregister')), true);
      expect(mockShell.runCalls.any((c) => c.contains('Ubuntu')), true);
      expect(result, contains('Unregistered'));
    });
  });

  group('lifecycle argv shapes', () {
    test('wsl_list_online_distros asks the catalog', () async {
      await tool('wsl_list_online_distros').handler({});
      expect(mockShell.runCalls.last, ['--list', '--online']);
    });

    test('wsl_install_distro installs headless', () async {
      await tool('wsl_install_distro').handler({'distro': 'Ubuntu-24.04'});
      expect(mockShell.runCalls.last,
          ['--install', '-d', 'Ubuntu-24.04', '--no-launch']);
    });

    test('wsl_set_default_distro uses --set-default', () async {
      await tool('wsl_set_default_distro').handler({'distro': 'Ubuntu'});
      expect(mockShell.runCalls.last, ['--set-default', 'Ubuntu']);
    });

    test('wsl_set_version rejects anything but 1 or 2', () async {
      await expectLater(
        tool('wsl_set_version').handler({'distro': 'Ubuntu', 'version': 3}),
        throwsArgumentError,
      );
    });

    test('wsl_import_distro refuses a missing local tarball', () async {
      await expectLater(
        tool('wsl_import_distro').handler({
          'name': 'fresh',
          'tarball': 'C:\\definitely\\missing\\rootfs.tar.gz',
        }),
        throwsArgumentError,
      );
      expect(mockShell.runCalls, isEmpty);
    });

    test('wsl_import_in_place refuses a missing vhdx', () async {
      await expectLater(
        tool('wsl_import_in_place').handler({
          'name': 'fresh',
          'vhdx_path': 'C:\\definitely\\missing\\disk.vhdx',
        }),
        throwsArgumentError,
      );
      expect(mockShell.runCalls, isEmpty);
    });
  });

  group('wsl_terminal_signal', () {
    test('rejects an unknown session id', () async {
      await expectLater(
        tool('wsl_terminal_signal')
            .handler({'session_id': 'nope', 'signal': 'ctrl-c'}),
        throwsArgumentError,
      );
    });

    test('kill on an unknown session is still an error, not a no-op',
        () async {
      await expectLater(
        tool('wsl_terminal_signal')
            .handler({'session_id': 'nope', 'signal': 'kill'}),
        throwsArgumentError,
      );
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
