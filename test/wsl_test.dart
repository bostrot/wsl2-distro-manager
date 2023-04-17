/// Tests for the wsl.dart file.
import 'dart:io';
import 'dart:ui';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wsl2distromanager/api/wsl.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/components/notify.dart';
import 'package:wsl2distromanager/dialogs/copy_dialog.dart';
import 'package:wsl2distromanager/dialogs/create_dialog.dart';

void main() {
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
    // Init bindings for tests
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized(); //<----FIX THE PROBLEM
    SharedPreferences.setMockInitialValues({});
    // Init prefs
    await initPrefs();

    Notify();
    Notify.message = statusMsg;
  });
  test('Check update', () async {
    App app = App();
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
    App app = App();
    var motd = await app.checkMotd();
    expect(motd, isNotEmpty);
  });

  test('Get distro links', () async {
    App app = App();
    var links = await app.getDistroLinks();
    expect(links, isNotEmpty);
  });

  test('UTF16 to UTF8', () {
    WSLApi app = WSLApi();
    // Create a UTF16 string
    var utf16 = 'Hello World';
    // To bytes
    var bytes = utf16.codeUnits;
    // Add 0 between each byte
    var bytes2 = bytes.expand((e) => [e, 0]).toList();

    // Convert to UTF8
    var utf8 = app.utf8Convert(bytes2);
    expect(utf8, utf16);
  });

  Future<bool> isInstance(String name) async {
    bool found = false;
    // Get list
    var list = await WSLApi().list(false);
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
      WSLApi(),
      TextEditingController(text: image),
      TextEditingController(text: user),
    );
  }

  test('Create instance test', () async {
    // Test with download
    final file = File('C:/WSL2-Distros/distros/Debian.tar.gz');
    if (await file.exists()) {
      await file.delete();
    }

    // Delete the instance
    await WSLApi().remove('test');
    expect(await isInstance('test'), false);

    // Test creating it
    await createDistro(
      'test',
      '',
      'Debian',
      '',
    );

    // Verify that the file exists and has > 2MB
    expect(await file.exists(), true);
    expect(await file.length(), greaterThan(2 * 1024 * 1024));
    expect(await isInstance('test'), true);

    // Delete the instance
    await WSLApi().remove('test');
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
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('Copy instance test', () async {
    // Old copy
    await WSLApi().copy('test', 'testcopy');
    expect(await isInstance('testcopy'), true);

    // New copy with vhd
    await WSLApi().stop('test');
    await WSLApi().copyVhd('test', 'testcopy2');

    expect(await isInstance('testcopy2'), true);

    // Delete the instance
    await WSLApi().remove('test');
    await WSLApi().remove('testcopy');
    await WSLApi().remove('testcopy2');

    expect(await isInstance('test'), false);
    expect(await isInstance('testcopy'), false);
    expect(await isInstance('testcopy2'), false);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
