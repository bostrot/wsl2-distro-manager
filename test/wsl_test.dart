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
import 'package:wsl2distromanager/api/wsl_conf.dart';
import 'package:wsl2distromanager/api/wslconfig.dart';
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

  /// The `/etc/wsl.conf` writer, end to end through the shell layer. The
  /// per-key behaviour lives in test/wsl_conf_test.dart; what is pinned here
  /// is the command WSLApi builds and the failure it reports.
  group('wsl.conf read/write', () {
    test('setSetting writes only the key it was given', () async {
      mockShell.wslConfContents =
          '# hand written\n[automount]\nenabled = true\n\n[interop]\nenabled = true\n';

      expect(await wslApi.setSetting('Ubuntu', 'interop', 'enabled', 'false'),
          true);

      // Audit CC-1: the old `sed` rewrote both `enabled` lines at once.
      expect(mockShell.wslConfContents,
          '# hand written\n[automount]\nenabled = true\n\n[interop]\nenabled = false\n');
    });

    test('a value full of shell metacharacters round-trips verbatim', () async {
      // Audit CC-2 / CC-7: `/` broke the sed delimiter and `"`, backticks and
      // `$(…)` ran as root inside the distro.
      const value = r'/usr/sbin/service docker start && echo "$(id)" `x`';
      mockShell.wslConfContents = '';

      expect(await wslApi.setSetting('Ubuntu', 'boot', 'command', value), true);
      expect((await wslApi.getWSLConf('Ubuntu'))['boot']!['command'], value);
    });

    test('a value with spaces and "=" survives', () async {
      mockShell.wslConfContents = '';
      await wslApi.setSetting(
          'Ubuntu', 'automount', 'options', 'metadata,uid=1000,gid=1000');
      await wslApi.setSetting('Ubuntu', 'boot', 'command', 'echo a = b');

      final config = await wslApi.getWSLConf('Ubuntu');
      expect(config['automount']!['options'], 'metadata,uid=1000,gid=1000');
      expect(config['boot']!['command'], 'echo a = b');
    });

    test('every documented key round-trips through the writer', () async {
      mockShell.wslConfContents = '';

      for (final section in kWslConfKeys.entries) {
        for (final key in section.value) {
          expect(await wslApi.setSetting('Ubuntu', section.key, key, 'v-$key'),
              true);
        }
      }

      final config = await wslApi.getWSLConf('Ubuntu');
      for (final section in kWslConfKeys.entries) {
        for (final key in section.value) {
          expect(config[section.key]?[key], 'v-$key',
              reason: '[${section.key}] $key did not survive');
        }
      }
    });

    test('the writer never puts a double quote in the command', () async {
      // runInShell is false, so a `"` reaches bash literally — see
      // lib/api/wsl_args.dart.
      mockShell.wslConfContents = '';
      await wslApi.setSetting('Ubuntu', 'network', 'hostname', 'my"host');

      expect(mockShell.lastRunArguments.last, isNot(contains('"')));
      expect(mockShell.lastRunArguments, containsAllInOrder(['-d', 'Ubuntu']));
      expect(mockShell.lastRunArguments, containsAllInOrder(['-u', 'root']));
      expect(mockShell.lastRunInShell, false);
      expect((await wslApi.getWSLConf('Ubuntu'))['network']!['hostname'],
          'my"host');
    });

    test('removeSetting deletes the line, leaving the rest', () async {
      mockShell.wslConfContents = '[boot]\nsystemd = true\ncommand = echo hi\n';

      expect(await wslApi.removeSetting('Ubuntu', 'boot', 'systemd'), true);
      expect(mockShell.wslConfContents, '[boot]\ncommand = echo hi\n');
    });

    test('removing a key that is not there does not rewrite the file',
        () async {
      mockShell.wslConfContents = '[boot]\nsystemd = true\n';
      mockShell.simulateWslConfReadOnly = true;

      // No write is attempted, so the read-only filesystem never comes up.
      expect(await wslApi.removeSetting('Ubuntu', 'boot', 'command'), true);
      expect(mockShell.wslConfContents, '[boot]\nsystemd = true\n');
    });

    test('a read-only /etc/wsl.conf reports failure', () async {
      mockShell.wslConfContents = '[boot]\nsystemd = true\n';
      mockShell.simulateWslConfReadOnly = true;

      // The old writer returned true unconditionally with showOutput: false,
      // so a failed write still showed as applied (audit CC-2).
      expect(
          await wslApi.setSetting('Ubuntu', 'boot', 'systemd', 'false'), false);
      expect(mockShell.wslConfContents, '[boot]\nsystemd = true\n');
    });

    test('an unreachable distro is never overwritten', () async {
      mockShell.wslConfContents = '[boot]\nsystemd = true\n';
      mockShell.simulateWslConfUnreachable = true;

      expect(
          await wslApi.setSetting('Ubuntu', 'network', 'hostname', 'x'), false);
      expect(await wslApi.getWSLConf('Ubuntu'), isEmpty);
      expect(mockShell.wslConfContents, '[boot]\nsystemd = true\n');
    });

    test('a distro with no wsl.conf gets one created', () async {
      mockShell.wslConfContents = null;

      expect(
          await wslApi.setSetting('Ubuntu', 'user', 'default', 'tester'), true);
      expect(mockShell.wslConfContents, '[user]\ndefault = tester\n');
    });
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

  /// P05-08, P05-16, P05-23 — wsl.exe verbs the audit found missing entirely
  /// (doc/audit/wsl-docs/cli-flags.md CC-1, CC-2).
  ///
  /// Every assertion here is about the **argument list**, because that is what
  /// those findings are about: `--manage` takes the distro before the option,
  /// and nothing may be assembled as a pre-quoted string — `runInShell: false`
  /// passes a `"` straight through to bash (AGENTS.md).
  group('wsl.exe verbs', () {
    test('--version and --status are asked, and answered', () async {
      mockShell.wslVersionOutput =
          'WSL version: 2.6.3.0\nKernel version: 6.6.87.2-1\n';
      mockShell.wslStatusOutput =
          'Default Distribution: Ubuntu\nDefault Version: 2\n';

      final capabilities = await wslApi.capabilities.load();
      expect(capabilities.version, '2.6.3.0');
      expect(capabilities.supportsManage, true);
      expect(capabilities.defaultDistro, 'Ubuntu');
      expect(mockShell.runCalls, contains(equals(['--version'])));
      expect(mockShell.runCalls, contains(equals(['--status'])));
    });

    test('--manage puts the distro before the option', () async {
      await wslApi.manageResize('Ubuntu', '256GB');
      expect(mockShell.manageCalls.single,
          ['--manage', 'Ubuntu', '--resize', '256GB']);
    });

    test('--set-sparse writes a bare true/false, never a quoted one', () async {
      await wslApi.manageSetSparse('Ubuntu', true);
      expect(mockShell.manageCalls.single,
          ['--manage', 'Ubuntu', '--set-sparse', 'true']);

      await wslApi.manageSetSparse('Ubuntu', false);
      expect(mockShell.manageCalls.last,
          ['--manage', 'Ubuntu', '--set-sparse', 'false']);

      for (final call in mockShell.manageCalls) {
        expect(call.any((arg) => arg.contains('"')), false);
      }
    });

    test('--set-default-user passes the name as one argument', () async {
      await wslApi.manageSetDefaultUser('Ubuntu', 'ada lovelace');
      expect(mockShell.manageCalls.single,
          ['--manage', 'Ubuntu', '--set-default-user', 'ada lovelace']);
    });

    test('--update takes --web-download only when asked', () async {
      await wslApi.updateWsl();
      expect(mockShell.updateCalls.single, ['--update']);

      await wslApi.updateWsl(webDownload: true);
      expect(mockShell.updateCalls.last, ['--update', '--web-download']);
    });

    test('--update hands back what wsl.exe said', () async {
      final result = await wslApi.updateWsl();
      expect(result.ok, true);
      expect(result.text, contains('already installed'));
    });

    test('diskUsage asks the system distro the documented question', () async {
      mockShell.dfOutput =
          'Filesystem     1K-blocks     Used Available Use% Mounted on\n'
          '/dev/sdd        104857600  1048576 103809024   1% /mnt/wslg/distro\n';

      final usage = await wslApi.diskUsage('Ubuntu');
      expect(mockShell.lastRunArguments,
          ['--system', '-d', 'Ubuntu', 'df', '-k', '/mnt/wslg/distro']);
      expect(usage!.usedBytes, 1048576 * 1024);
      expect(usage.totalBytes, 104857600 * 1024);
    });

    test('a distro that cannot answer df yields null, not zeroes', () async {
      mockShell.dfOutput = '';
      expect(await wslApi.diskUsage('Ubuntu'), isNull);
    });
  });

  /// P05-15. #280 is the one finding in this audit with a report of real data
  /// loss behind it: the old move exports to a tar, **unregisters** the distro
  /// and imports it back, and the reporter's distro vanished inside that
  /// window. `--manage --move` has no such window.
  group('move prefers the native verb (P05-15)', () {
    setUp(() {
      mockShell.wslVersionOutput = 'WSL version: 2.6.3.0\n';
    });

    test('on WSL 2.5+ it issues one --manage --move and never unregisters',
        () async {
      mockShell.distros.add('nativemove');
      File('C:/WSL2-Distros/nativemove/ext4.vhdx').createSync(recursive: true);

      await wslApi.move('nativemove', 'C:/WSL2-Distros/nativemove-target');

      expect(mockShell.manageCalls.single, [
        '--manage',
        'nativemove',
        '--move',
        'C:/WSL2-Distros/nativemove-target',
      ]);
      // The destructive path's three steps, none of which ran.
      expect(
          mockShell.runCalls.any((call) => call.contains('--export')), false);
      expect(mockShell.runCalls.any((call) => call.contains('--unregister')),
          false);
      expect(
          mockShell.runCalls.any((call) => call.contains('--import')), false);
      expect(mockShell.distros, contains('nativemove'));
      expect(prefs.getString('Path_nativemove'),
          'C:/WSL2-Distros/nativemove-target');

      await Directory('C:/WSL2-Distros/nativemove-target')
          .delete(recursive: true);
    });

    test('the distro is terminated first, because a running one holds the VHD',
        () async {
      mockShell.distros.add('nativemove2');
      await wslApi.move('nativemove2', 'C:/WSL2-Distros/nativemove2-target');

      final terminate =
          mockShell.runCalls.indexWhere((c) => c.contains('--terminate'));
      final move = mockShell.runCalls.indexWhere((c) => c.contains('--move'));
      expect(terminate, greaterThanOrEqualTo(0));
      expect(move, greaterThan(terminate));

      await Directory('C:/WSL2-Distros/nativemove2-target')
          .delete(recursive: true);
    });

    test('supportsNativeMove reflects the installed build', () async {
      expect(await wslApi.supportsNativeMove(), true);

      final inbox = WSLApi(shell: MockShell()..wslVersionExitCode = 1);
      expect(await inbox.supportsNativeMove(), false);
    });

    test('a failed native move never falls back to the destructive path',
        () async {
      // Retrying a recoverable failure with export → unregister → import is
      // how a recoverable error becomes an unrecoverable one.
      mockShell.distros.add('failmove');
      mockShell.manageFailure = 'The system cannot find the path specified.';

      await expectLater(
          () => wslApi.move('failmove', 'C:/WSL2-Distros/failmove-target'),
          throwsA(
              predicate((e) => e.toString().contains('cannot find the path'))));

      expect(mockShell.distros, contains('failmove'));
      expect(mockShell.runCalls.any((call) => call.contains('--unregister')),
          false);
      expect(prefs.getString('MoveOp_Distro'), isNull);
    });

    test('a no-op move is refused before anything runs', () async {
      mockShell.distros.add('samepath');
      await expectLater(
          () => wslApi.move('samepath', getInstancePath('samepath').path),
          throwsA(
              predicate((e) => e.toString().contains('must be different'))));
      expect(mockShell.manageCalls, isEmpty);
    });

    test('an empty target is refused rather than resolved to the cwd',
        () async {
      // p.canonicalize('') is the process's working directory, which is not
      // where anyone means to put a distro.
      mockShell.distros.add('notarget');
      await expectLater(() => wslApi.move('notarget', '   '),
          throwsA(predicate((e) => e.toString().contains('no target path'))));
      expect(mockShell.manageCalls, isEmpty);
    });
  });

  /// P05-02 at the API boundary. The model is covered end to end in
  /// test/wslconfig_test.dart; these two pin the routing decisions `saveSettings`
  /// depends on. Nothing here touches the real `%UserProfile%\.wslconfig`.
  group('.wslconfig section routing (P05-02)', () {
    test('an experimental key is written to [experimental], never [wsl2]',
        () async {
      // Runtime R-4: all seven are *rejected* under [wsl2] and the setting is
      // silently off, with only a stderr line to say so.
      final config = WslConfigFile.parse('[wsl2]\nmemory = 8GB\n');
      config.set(config.sectionFor('sparseVhd'), 'sparseVhd', 'true');

      expect(config.get('experimental', 'sparseVhd'), 'true');
      expect(config.get('wsl2', 'sparseVhd'), isNull);
      expect(config.serialize(), startsWith('[wsl2]\nmemory = 8GB\n'));
    });

    test('an unreachable remote host reads as null, never as an empty file',
        () async {
      // The difference readWSLConf already draws for wsl.conf: an *unreadable*
      // config must not come back as an *empty* one, or the next Save replaces
      // the remote host's whole configuration with the one key the user
      // touched.
      SharedPreferences.setMockInitialValues({
        'DistroPath': defaultPath,
        'UseRemoteWSL': true,
        'RemoteWSLTarget': 'user@host',
      });
      prefs = await SharedPreferences.getInstance();
      addTearDown(() async {
        SharedPreferences.setMockInitialValues({'DistroPath': defaultPath});
        prefs = await SharedPreferences.getInstance();
      });

      final unreachable = WSLApi(shell: MockShell()..sshFails = true);
      expect(await unreachable.readWslConfig(), isNull);
      expect(await unreachable.readConfig(), isEmpty);
      expect(
          await unreachable
              .updateWslConfig((c) => c.set('wsl2', 'memory', '1GB')),
          false);
    });

    test('readConfig flattens only the sections the app knows', () async {
      final config = WslConfigFile.parse(
          '[wsl2]\nmemory = 8GB\n\n[experimental]\nsparseVhd = true\n'
          '\n[future]\nsomething = 1\n');
      expect(config.flatten(), {'memory': '8GB', 'sparseVhd': 'true'});
    });
  });
}
