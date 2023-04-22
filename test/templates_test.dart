/// Tests for the wsl.dart file.
import 'dart:io';
import 'dart:ui';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wsl2distromanager/api/templates.dart';
import 'package:wsl2distromanager/api/wsl.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/components/notify.dart';
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

  createDistro(name, loc, image, user) async {
    await createInstance(
      TextEditingController(text: name),
      TextEditingController(text: loc),
      WSLApi(),
      TextEditingController(text: image),
      TextEditingController(text: user),
    );
  }

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

  // Stuff before tests
  setUpAll(() async {
    // Init bindings for tests
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    // Init prefs
    await initPrefs();

    Notify();
    Notify.message = statusMsg;

    // Delete the instance
    await WSLApi().remove('test');

    // Create test instance
    await createDistro(
      'test',
      '',
      'Debian',
      '',
    );

    expect(await isInstance('test'), true);

    // Create file testfile in test instance
    var res = await WSLApi().execCmdAsRoot('test', 'touch /testfile');

    expect(res, "");
  });

  tearDownAll(() {
    // Delete the instance
    WSLApi().remove('test');
    WSLApi().remove('test2');
    Templates().deleteTemplate('test');
    Templates().deleteTemplate('test-2');
    Templates().deleteTemplate('test-3');
  });

  test('Create template', () async {
    await Templates().saveTemplate('test');
    expect(File(Templates().getTemplateFilePath('test')).existsSync(), true);
  });

  test('Create template of already existent', () async {
    await Templates().saveTemplate('test');
    expect(File(Templates().getTemplateFilePath('test')).existsSync(), true);
    await Templates().saveTemplate('test');
    expect(File(Templates().getTemplateFilePath('test-2')).existsSync(), true);
    await Templates().saveTemplate('test');
    expect(File(Templates().getTemplateFilePath('test-3')).existsSync(), true);
  });

  test('Use template', () async {
    await Templates().useTemplate('test', 'test2');
    expect(await isInstance('test2'), true);

    // Check if testfile exists
    var res = await WSLApi().execCmdAsRoot('test2', 'ls /testfile');
    expect(res, "/testfile\n");
  });

  test('Delete template', () async {
    await Templates().deleteTemplate('test');
    expect(File(Templates().getTemplateFilePath('test')).existsSync(), false);
  });
}
