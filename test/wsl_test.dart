/// Tests for the wsl.dart file.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wsl2distromanager/api/app.dart';
import 'package:wsl2distromanager/api/wsl.dart';
import 'package:wsl2distromanager/components/constants.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/components/notify.dart';
import 'package:wsl2distromanager/dialogs/create_dialog.dart';

import 'mocks.dart';

void main() {
  late MockShell mockShell;
  late WSLApi wslApi;
  late Dio mockDio;
  late List<String> statusMessages;

  void statusMsg(
    String msg, {
    Duration? duration,
    dynamic severity = "",
    bool loading = false,
    bool useWidget = false,
    bool leadingIcon = true,
    dynamic widget,
  }) {
    statusMessages.add(msg);
  }

  // Stuff before tests
  setUpAll(() async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    // Pin the distro root: these tests stage fixtures under C:\WSL2-Distros,
    // so they must not depend on the per-user default storage root
    // (%APPDATA%) that getDistroPath() otherwise falls back to.
    SharedPreferences.setMockInitialValues({'DistroPath': defaultPath});
    await initPrefs();

    Notify();
    Notify.message = statusMsg;
  });

  setUp(() {
    mockShell = MockShell();
    wslApi = WSLApi(shell: mockShell);
    mockDio = Dio();
    mockDio.httpClientAdapter = MockHttpClientAdapter();
    statusMessages = [];
  });

  test('Check update', () async {
    App app = App(dio: mockDio);
    var updateUrl = await app.checkUpdate('1.0.0');
    // Check if updateUrl contains https:// and .msix
    expect(updateUrl.contains('https://'), true);
    expect(updateUrl.contains('.msix'), true);
  });

  test('Version to double', () {
    App app = App();
    var version = app.versionToDouble('1.0.0');
    expect(version, 100.0);
  });

  test('Check motd', () async {
    App app = App(dio: mockDio);
    var motd = await app.checkMotd();
    expect(motd, isNotEmpty);
  });

  test('Get distro links', () async {
    App app = App(dio: mockDio);
    var links = await app.getDistroLinks();
    expect(links, isNotEmpty);
  });

  test('UTF16 to UTF8', () {
    var utf16 = 'Hello World';
    var bytes = utf16.codeUnits;
    var bytes2 = bytes.expand((e) => [e, 0]).toList();

    var utf8 = wslApi.utf8Convert(bytes2);
    expect(utf8, utf16);
  });

  test('utf8Convert preserves unicode characters', () {
    final text = '错误: 路径无效';
    final converted = wslApi.utf8Convert(utf8.encode(text));
    expect(converted, text);
  });

  Future<bool> isInstance(String name) async {
    bool found;
    // Get list
    var list = await wslApi.list(false);
    found = false;

    for (var item in list.all) {
      if (item == name) {
        found = true;
      }
    }
    return found;
  }

  createDistro(name, loc, image, user) async {
    await createInstance(
      TextEditingController(text: name),
      TextEditingController(text: loc),
      wslApi,
      TextEditingController(text: image),
      TextEditingController(text: user),
    );
  }

  test('Create instance test', () async {
    // Save original state of distroRootfsLinks and restore after test to prevent test pollution
    final originalDistroRootfsLinks =
        Map<String, String>.from(distroRootfsLinks);
    addTearDown(() {
      distroRootfsLinks
        ..clear()
        ..addAll(originalDistroRootfsLinks);
    });
    // Test with download
    distroRootfsLinks['Debian'] = 'http://example.com/debian.tar.gz';

    final file = File('C:/WSL2-Distros/distros/Debian.tar.gz');
    if (!await file.exists()) {
      file.createSync(recursive: true);
    }

    // Delete the instance
    await wslApi.remove('test');
    expect(await isInstance('test'), false);

    // Test creating it
    await createDistro(
      'test',
      '',
      'Debian',
      '',
    );

    // Verify that the file exists
    expect(await file.exists(), true);
    expect(await isInstance('test'), true);

    // Delete the instance
    await wslApi.remove('test');
    expect(await isInstance('test'), false);

    // Test without download
    // Test creating it
    await createDistro(
      'test',
      '',
      'Debian',
      '',
    );

    expect(await isInstance('test'), true);
  });

  test('Create instance shows stderr on import failure', () async {
    mockShell.simulateInvalidPath = true;
    mockShell.importFailureStdout = 'cOv...NO';

    await createDistro(
      'test',
      '',
      '/tmp/non-existent-template.tar.gz',
      '',
    );

    expect(
      statusMessages.any((m) => m.contains('Invalid installation path')),
      true,
    );
    expect(statusMessages.any((m) => m.contains('cOv...NO')), false);
  });

  test('Copy instance test', () async {
    // Setup: create 'test'
    mockShell.distros.add('test');
    File('C:/WSL2-Distros/test/ext4.vhdx').createSync(recursive: true);

    // Old copy
    await wslApi.copy('test', 'testcopy');
    expect(await isInstance('testcopy'), true);

    // New copy with vhd
    await wslApi.stop('test');
    await wslApi.copyVhd('test', 'testcopy2');

    expect(await isInstance('testcopy2'), true);

    // Delete the instance
    await wslApi.remove('test');
    await wslApi.remove('testcopy');
    await wslApi.remove('testcopy2');

    expect(await isInstance('test'), false);
    expect(await isInstance('testcopy'), false);
    expect(await isInstance('testcopy2'), false);
  });

  test('Cleanup test', () async {
    // Create a new instance
    mockShell.distros.add('test');
    File('C:/WSL2-Distros/test/ext4.vhdx').createSync(recursive: true);

    // Cleanup
    String result = await wslApi.cleanup('test');

    // Should return success message
    expect(result, contains('Cleanup completed successfully'));

    // Still exists (cleanup re-imports it)
    expect(await isInstance('test'), true);

    // Check that export file is cleaned up (should not exist after successful cleanup)
    var exportFile = File('C:/WSL2-Distros/test/export.tar.gz');
    expect(await exportFile.exists(), false);
  });

  test('Cleanup test with nonexistent instance', () async {
    const name = 'nonexistent-instance';

    try {
      var result = await wslApi.cleanup(name);

      final lower = result.toLowerCase();
      final handled = lower.contains('not found') ||
          lower.contains('does not exist') ||
          lower.contains('no such') ||
          lower.contains('error') ||
          lower.contains('not exist');

      expect(handled, true,
          reason:
              'cleanup returned a message but it did not indicate a missing instance or an error: "$result"');
    } catch (e) {
      expect(e, isA<Exception>());
    }
  });

  test('Move distro', () async {
    mockShell.distros.add('test');
    File('C:/WSL2-Distros/test/ext4.vhdx').createSync(recursive: true);

    await wslApi.move('test', 'C:/WSL2-Distros/test-moved');

    var file = File('C:/WSL2-Distros/test-moved/ext4.vhdx');
    expect(await file.exists(), true);

    expect(await isInstance('test'), true);

    await wslApi.remove('test');
    expect(await isInstance('test'), false);

    if (await Directory('C:/WSL2-Distros/test-moved').exists()) {
      await Directory('C:/WSL2-Distros/test-moved').delete(recursive: true);
    }
  });

  test('Check if instance exists', () async {
    expect(await isInstance('test'), false);
  });

  group('Editor Settings', () {
    test('Default editor is notepad.exe', () async {
      prefs.remove('Editor');
      wslApi.editConfig();
      // Wait for async execution
      await Future.delayed(Duration.zero);

      expect(mockShell.lastStartArguments, contains('notepad.exe'));
    });

    test('Custom editor is used', () async {
      prefs.setString('Editor', 'code.exe');
      wslApi.editConfig();
      // Wait for async execution
      await Future.delayed(Duration.zero);

      expect(mockShell.lastStartArguments, contains('code.exe'));
    });

    test('Open bashrc uses custom editor', () async {
      prefs.setString('Editor', 'vim.exe');
      await wslApi.openBashrc('Ubuntu');

      expect(mockShell.lastStartArguments, contains('vim.exe'));
    });
  });

  group('Terminal Tests', () {
    test('WSL start with custom terminal', () async {
      prefs.setString('Terminal', 'custom_terminal.exe');
      wslApi.start('Ubuntu');
      // Wait for async
      await Future.delayed(const Duration(milliseconds: 100));
      expect(mockShell.lastStartExecutable, 'custom_terminal.exe');
      expect(mockShell.lastStartArguments, contains('wsl'));
      expect(mockShell.lastStartArguments, contains('-d'));
      expect(mockShell.lastStartArguments, contains('Ubuntu'));
      prefs.remove('Terminal');
    });

    test('WSL start with default terminal', () async {
      prefs.remove('Terminal');
      wslApi.start('Ubuntu');
      // Wait for async
      await Future.delayed(const Duration(milliseconds: 100));
      expect(mockShell.lastStartExecutable, 'start');
      expect(mockShell.lastStartArguments, contains('wsl'));
      expect(mockShell.lastStartArguments, contains('-d'));
      expect(mockShell.lastStartArguments, contains('Ubuntu'));
    });
  });

  group('Remote WSL Tests', () {
    setUp(() {
      prefs.setBool('UseRemoteWSL', true);
      prefs.setString('RemoteWSLTarget', 'user@192.168.1.20');
    });

    tearDown(() {
      prefs.remove('UseRemoteWSL');
      prefs.remove('RemoteWSLTarget');
    });

    test('useRemoteWsl is false with a malformed target', () async {
      prefs.setString('RemoteWSLTarget', '-not-a-valid-target');
      expect(wslApi.useRemoteWsl, false);
    });

    test('useRemoteWsl is false when the toggle is off', () async {
      prefs.setBool('UseRemoteWSL', false);
      expect(wslApi.useRemoteWsl, false);
    });

    test('useRemoteWsl is true with a valid target and toggle on', () async {
      expect(wslApi.useRemoteWsl, true);
    });

    // Regression coverage for a real bug: start()/openBashrc()/startVSCode()/
    // exec()'s passwd branch launch via Windows `start`/a terminal exe with
    // 'ssh' as part of the *argument list*, not as the process executable
    // (unlike _runWsl/_startWsl, which pass 'ssh' as the executable
    // directly). They previously built their args via _buildRemoteArgs alone
    // — which only returns ssh's own options, never the literal 'ssh' token —
    // so remote terminal/editor/VS Code launches silently passed SSH's
    // options (`-o`, `BatchMode=yes`, ...) as the program to run instead of
    // running ssh at all.
    test('start() prefixes remote args with the literal ssh token', () async {
      prefs.remove('Terminal');
      wslApi.start('Ubuntu');
      await Future.delayed(const Duration(milliseconds: 100));

      expect(mockShell.lastStartExecutable, 'start');
      expect(mockShell.lastStartArguments.first, 'ssh');
      expect(mockShell.lastStartArguments, contains('user@192.168.1.20'));
      expect(mockShell.lastStartArguments, contains('wsl'));
      expect(mockShell.lastStartArguments, contains('-d'));
      expect(mockShell.lastStartArguments, contains('Ubuntu'));
    });

    test('openBashrc() prefixes remote args with the literal ssh token',
        () async {
      await wslApi.openBashrc('Ubuntu');

      expect(mockShell.lastStartExecutable, 'start');
      expect(mockShell.lastStartArguments.first, 'ssh');
      expect(mockShell.lastStartArguments, contains('user@192.168.1.20'));
      expect(mockShell.lastStartArguments, contains('wsl'));
    });

    test('startVSCode() prefixes remote args with the literal ssh token',
        () async {
      wslApi.startVSCode('Ubuntu');
      await Future.delayed(const Duration(milliseconds: 100));

      expect(mockShell.lastStartExecutable, 'start');
      expect(mockShell.lastStartArguments, containsAllInOrder(['/b', 'ssh']));
      expect(mockShell.lastStartArguments, contains('user@192.168.1.20'));
      expect(mockShell.lastStartArguments, contains('code'));
    });

    test('exec() passwd branch prefixes remote args with the literal ssh token',
        () async {
      await wslApi.exec('Ubuntu', ['passwd']);

      expect(mockShell.lastStartExecutable, 'start');
      expect(mockShell.lastStartArguments.first, 'ssh');
      expect(mockShell.lastStartArguments, contains('user@192.168.1.20'));
    });

    test('stop() routes through ssh as the process executable, not the arg list',
        () async {
      await wslApi.stop('Ubuntu');

      // _runWsl passes 'ssh' as the executable itself (correct pattern —
      // contrast with the start()/openBashrc()/etc. cases above, which
      // launch through a different executable and need 'ssh' inlined into
      // the argument list instead).
      expect(mockShell.lastRunExecutable, 'ssh');
      expect(mockShell.lastRunArguments, contains('user@192.168.1.20'));
      expect(mockShell.lastRunArguments, contains('--terminate'));
      expect(mockShell.lastRunArguments, contains('Ubuntu'));
    });

    test('remoteInstallPath builds a path under the shared remote root',
        () async {
      expect(wslApi.remoteInstallPath('Ubuntu'),
          r'C:\wsl2dm\instances\Ubuntu');
    });

    // Regression coverage for a real gap: the remote move() branch used to
    // skip every safety net the local branch has (same-path check,
    // minimum-export-size check, recovery markers) — a bad/truncated
    // remote export could get the source distro deleted before anyone
    // noticed. Both checks below must reject *before* remove() runs.
    test('move() remote rejects a no-op move to the same path', () async {
      mockShell.distros.add('Ubuntu');
      prefs.setString('Path_Ubuntu', r'C:\wsl2dm\instances\Ubuntu');

      await expectLater(
        () => wslApi.move('Ubuntu', r'C:\wsl2dm\instances\Ubuntu'),
        throwsA(predicate((e) =>
            e.toString().contains('must be different from current path'))),
      );
      // The distro must still be registered — remove() was never reached.
      expect(mockShell.distros, contains('Ubuntu'));
      prefs.remove('Path_Ubuntu');
    });

    test('move() remote rejects a too-small export and never removes the distro',
        () async {
      mockShell.distros.add('Ubuntu');
      mockShell.remoteFileSizeBytes = 512; // well under the 1MB safety floor

      await expectLater(
        () => wslApi.move('Ubuntu', r'C:\wsl2dm\instances\UbuntuMoved'),
        throwsA(predicate(
            (e) => e.toString().contains('Export failed or file too small'))),
      );
      expect(mockShell.distros, contains('Ubuntu'));
      expect(prefs.getString('MoveOp_Distro'), isNull);
    });
  });

  test('WSL getWSLConf parses correctly', () async {
    // Mock execCmdAsRoot to return sample config
    mockShell.execCmdAsRootResponse = '''
[automount]
enabled = true
options = "metadata,uid=1000,gid=1000,umask=022,fmask=11,case=off"
mountFsTab = true

[network]
generateHosts = true
hostname = MyHost

[boot]
systemd = true
''';

    var config = await wslApi.getWSLConf('Ubuntu');

    expect(config['automount']!['enabled'], 'true');
    expect(config['automount']!['mountFsTab'], 'true');
    expect(config['automount']!['options'],
        '"metadata,uid=1000,gid=1000,umask=022,fmask=11,case=off"');
    expect(config['network']!['generateHosts'], 'true');
    expect(config['network']!['hostname'], 'MyHost');
    expect(config['boot']!['systemd'], 'true');
  });

  test('Move distro fails if export is too small', () async {
    mockShell.distros.add('test-small');
    mockShell.simulateSmallExport = true;
    File('C:/WSL2-Distros/test/ext4.vhdx').createSync(recursive: true);

    // Keep DistroPath pinned across this reset — the fixtures live under
    // C:\WSL2-Distros, not the per-user default storage root.
    SharedPreferences.setMockInitialValues({'DistroPath': defaultPath});
    prefs = await SharedPreferences.getInstance();

    try {
      await wslApi.move('test-small', 'C:/WSL2-Distros/test-moved-small');
      fail('Should have thrown exception');
    } catch (e) {
      expect(e.toString(), contains('Export failed or file too small'));
    }

    // Verify markers are NOT set (failed before setting them)
    expect(prefs.getString('MoveOp_Distro'), null);
    expect(prefs.getString('MoveOp_BackupPath'), null);
  });

  test('Move distro sets recovery markers on failure during remove', () async {
    mockShell.distros.add('test-fail-remove');
    mockShell.simulateRemoveFailure = true;
    File('C:/WSL2-Distros/test/ext4.vhdx').createSync(recursive: true);

    // Keep DistroPath pinned across this reset — the fixtures live under
    // C:\WSL2-Distros, not the per-user default storage root.
    SharedPreferences.setMockInitialValues({'DistroPath': defaultPath});
    prefs = await SharedPreferences.getInstance();

    try {
      await wslApi.move('test-fail-remove', 'C:/WSL2-Distros/test-moved-fail');
      fail('Should have thrown exception');
    } catch (e) {
      // Expected failure from remove
    }

    // Verify markers ARE set (failed after setting them but before clearing)
    expect(prefs.getString('MoveOp_Distro'), 'test-fail-remove');
    expect(prefs.getString('MoveOp_BackupPath'), contains('export.ext4'));
  });

  test('Move distro clears recovery markers on success', () async {
    mockShell.distros.add('test-success');
    File('C:/WSL2-Distros/test/ext4.vhdx').createSync(recursive: true);

    // Keep DistroPath pinned across this reset — the fixtures live under
    // C:\WSL2-Distros, not the per-user default storage root.
    SharedPreferences.setMockInitialValues({'DistroPath': defaultPath});
    prefs = await SharedPreferences.getInstance();

    // Manually set markers to ensure they get cleared
    await prefs.setString('MoveOp_Distro', 'test-success');
    await prefs.setString('MoveOp_BackupPath', 'dummy/path');

    await wslApi.move('test-success', 'C:/WSL2-Distros/test-moved-success');

    // Verify markers are CLEARED
    expect(prefs.getString('MoveOp_Distro'), null);
    expect(prefs.getString('MoveOp_BackupPath'), null);
  });

  test('startVSCode uses preference if set', () async {
    SharedPreferences.setMockInitialValues({'VSCodeCmd': 'custom-code'});
    prefs = await SharedPreferences.getInstance();

    wslApi.startVSCode('Ubuntu');

    // Wait for async execution (startVSCode is async void)
    await Future.delayed(const Duration(milliseconds: 10));

    expect(mockShell.lastStartArguments, contains('custom-code'));
  });

  test('startVSCode defaults to code if not set', () async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();

    wslApi.startVSCode('Ubuntu');
    await Future.delayed(const Duration(milliseconds: 10));

    expect(mockShell.lastStartArguments, contains('code'));
  });

  group('Issue regressions', () {
    setUp(() async {
      // Earlier tests in this file reset the mock prefs, which drops the
      // pinned distro root that these fixtures live under.
      SharedPreferences.setMockInitialValues({'DistroPath': defaultPath});
      prefs = await SharedPreferences.getInstance();
    });

    test('remove() drops every preference keyed by the distro name', () async {
      mockShell.distros.add('stale');
      for (final prefix in distroPrefKeyPrefixes) {
        await prefs.setString('$prefix' 'stale', 'x');
      }

      await wslApi.remove('stale');

      for (final prefix in distroPrefKeyPrefixes) {
        expect(prefs.get('$prefix' 'stale'), isNull,
            reason: '$prefix should have been cleared');
      }
    });

    test('cleanup() finds the disk when the stored path is stale', () async {
      mockShell.distros.add('moved');
      File('C:/WSL2-Distros/moved/ext4.vhdx').createSync(recursive: true);
      await prefs.setString('Path_moved', r'C:\gone\moved');

      final result = await wslApi.cleanup('moved');

      expect(result, contains('Cleanup completed successfully'));
      // The stale entry is corrected to where the disk actually is.
      expect(prefs.getString('Path_moved'), contains('moved'));
      expect(prefs.getString('Path_moved'), isNot(contains('gone')));
    });

    test('cleanup() lists the paths it tried when nothing is found', () async {
      mockShell.distros.add('missing-disk');
      await prefs.setString('Path_missing-disk', r'C:\nowhere');

      await expectLater(
        wslApi.cleanup('missing-disk'),
        throwsA(predicate((e) => e.toString().contains('nowhere'))),
      );
    });

    test('startVSCode() opens the default user home when no path is stored',
        () async {
      await wslApi.startVSCode('Ubuntu');
      await Future.delayed(const Duration(milliseconds: 50));

      expect(mockShell.lastStartArguments, contains('/home/tester'));
    });

    test('startVSCode() still honours an explicit path', () async {
      await wslApi.startVSCode('Ubuntu', path: '/srv/project');
      await Future.delayed(const Duration(milliseconds: 50));

      expect(mockShell.lastStartArguments, contains('/srv/project'));
      expect(mockShell.lastStartArguments, isNot(contains('/home/tester')));
    });
  });

  // Regression guard for the `bash: -c: line 2: syntax error near unexpected
  // token` class of failure: wsl.exe re-joins its argv and re-parses it
  // through the distro's default shell unless `--exec` is present, so a
  // pre-split command loses its quoting on the way in.
  // See lib/api/wsl_args.dart.
  group('in-distro invocations go through wsl_args', () {
    test('execCmdAsRoot hands the whole command to bash -c behind --exec',
        () async {
      await wslApi.execCmdAsRoot('Ubuntu', "echo 'hello world' > /tmp/out");

      expect(mockShell.lastRunExecutable, 'wsl');
      expect(mockShell.lastRunArguments, [
        '-d',
        'Ubuntu',
        '-u',
        'root',
        '--exec',
        'bash',
        '-c',
        "echo 'hello world' > /tmp/out",
      ]);
    });

    test('execCmdAsRoot does not pre-split the command into argv', () async {
      await wslApi.execCmdAsRoot('Ubuntu', 'ls -la /etc');

      // The old form appended splitShellArgs() to the argument list, which
      // stripped quotes and left the re-parse to do the rest.
      expect(mockShell.lastRunArguments, isNot(contains('-la')));
      expect(mockShell.lastRunArguments.last, 'ls -la /etc');
    });

    test('execCmdAsRoot does not run through cmd.exe', () async {
      // runInShell: true would let cmd.exe eat &, |, <, > and ^ before
      // wsl.exe ever saw them.
      await wslApi.execCmdAsRoot('Ubuntu', 'cat /proc/net/tcp');
      expect(mockShell.lastRunInShell, isFalse);
    });

    test('exec() keeps a quoted redirection intact', () async {
      const cmd =
          "echo 'tester ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers.d/wslsudo";
      await wslApi.exec('Ubuntu', [cmd]);

      expect(mockShell.lastRunArguments,
          ['-d', 'Ubuntu', '--exec', 'bash', '-c', cmd]);
      // The bare `(` that the old split left behind is what the distro's
      // shell choked on.
      expect(mockShell.lastRunArguments, isNot(contains('ALL=(ALL)')));
    });

    test('getDefaultUser execs whoami rather than letting a shell see it',
        () async {
      await wslApi.getDefaultUser('Ubuntu');
      expect(mockShell.lastRunArguments, ['-d', 'Ubuntu', '--exec', 'whoami']);
    });

    test('getDefaultUserHome passes the HOME echo through sh -c', () async {
      await wslApi.getDefaultUserHome('Ubuntu');
      expect(mockShell.lastRunArguments,
          ['-d', 'Ubuntu', '--exec', 'sh', '-c', r'echo $HOME']);
    });

    test('start() keeps the default-shell re-parse it depends on', () async {
      // The trailing `;/bin/sh` only becomes a second command because the
      // distro's shell re-parses the flattened argv — this one call site must
      // NOT gain --exec.
      wslApi.start('Ubuntu', startCmd: 'htop');
      await Future.delayed(const Duration(milliseconds: 50));

      expect(mockShell.lastStartArguments, contains(';/bin/sh'));
      expect(mockShell.lastStartArguments, isNot(contains('--exec')));
    });
  });
}
