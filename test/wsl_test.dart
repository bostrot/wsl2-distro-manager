/// Tests for the wsl.dart file.
import 'dart:async';
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

  void statusMsg(
    String msg, {
    Duration? duration,
    dynamic severity = "",
    bool loading = false,
    bool useWidget = false,
    bool leadingIcon = true,
    dynamic widget,
  }) {}

  // Stuff before tests
  setUpAll(() async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await initPrefs();

    Notify();
    Notify.message = statusMsg;
  });

  setUp(() {
    mockShell = MockShell();
    wslApi = WSLApi(shell: mockShell);
    mockDio = Dio();
    mockDio.httpClientAdapter = MockHttpClientAdapter();
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

    SharedPreferences.setMockInitialValues({});
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

    SharedPreferences.setMockInitialValues({});
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

    SharedPreferences.setMockInitialValues({});
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
}
