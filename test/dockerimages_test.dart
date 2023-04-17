// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility that Flutter provides. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wsl2distromanager/api/docker_images.dart';
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

  test('Create instance test alpine', () async {
    TextEditingController nameController = TextEditingController(text: 'test');
    TextEditingController locationController = TextEditingController(text: '');
    TextEditingController autoSuggestBox =
        TextEditingController(text: 'dockerhub:alpine:latest');

    final file = File('C:/WSL2-Distros/distros/library_alpine_latest.tar.gz');
    if (await file.exists()) {
      await file.delete();
    }

    // Test build context
    await createInstance(
      nameController,
      locationController,
      WSLApi(),
      autoSuggestBox,
      TextEditingController(text: ''),
    );

    // Verify that the file exists and has > 2MB
    expect(await file.exists(), true);
    expect(await file.length(), greaterThan(2 * 1024 * 1024));

    expect(await isInstance('test'), true);

    // Delete the instance
    await WSLApi().remove('test');

    expect(await isInstance('test'), false);

    // Test creating it without re-downloading the rootfs
    await createInstance(
      nameController,
      locationController,
      WSLApi(),
      autoSuggestBox,
      TextEditingController(text: ''),
    );

    expect(await isInstance('test'), true);

    // Delete the instance
    await WSLApi().remove('test');
  });

  test('Create instance test nginx (nonroot)', () async {
    TextEditingController nameController = TextEditingController(text: 'test');
    TextEditingController locationController = TextEditingController(text: '');
    TextEditingController autoSuggestBox =
        TextEditingController(text: 'dockerhub:bitnami/nginx:latest');

    final file = File('C:/WSL2-Distros/distros/bitnami_nginx_latest.tar.gz');
    if (await file.exists()) {
      await file.delete();
    }

    // Delete the instance
    await WSLApi().remove('test');

    // Test build context
    await createInstance(
      nameController,
      locationController,
      WSLApi(),
      autoSuggestBox,
      TextEditingController(text: ''),
    );

    // Verify that the file exists and has > 2MB
    expect(await file.exists(), true);
    expect(await file.length(), greaterThan(2 * 1024 * 1024));
    expect(await isInstance('test'), true);

    // Delete the instance
    await WSLApi().remove('test');

    expect(await isInstance('test'), false);

    // Test creating it without re-downloading the rootfs
    await createInstance(
      nameController,
      locationController,
      WSLApi(),
      autoSuggestBox,
      TextEditingController(text: ''),
    );

    expect(await isInstance('test'), true);

    // Delete the instance
    await WSLApi().remove('test');
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('Docker rootfs download single layer', () async {
    const String image = 'library/alpine';
    const String tag = 'latest';
    const String distroPath = 'C:/WSL2-Distros/distros';
    final String filename = DockerImage().filename(image, tag);

    final file = File('$distroPath/$filename.tar.gz');
    if (await file.exists()) {
      await file.delete();
    }

    // Get rootfs
    await DockerImage().getRootfs("test", image, tag: tag,
        progress: ((count, total, countStep, totalStep) {
      if (kDebugMode) {
        print('Downloading $count/$total ($countStep/$totalStep)');
      }
    }));

    // Verify that the file exists and has > 2MB
    expect(await file.exists(), true);
    expect(await file.length(), greaterThan(2 * 1024 * 1024));
  });

// timeout test 2 minutes
  test('Docker rootfs download multi layer', () async {
    const String image = 'jekyll/jekyll';
    const String tag = 'latest';
    const String distroPath = 'C:/WSL2-Distros/distros';
    final String filename = DockerImage().filename(image, tag);
    // Get rootfs
    await DockerImage().getRootfs("test", image, tag: tag, skipDownload: false,
        progress: ((count, total, countStep, totalStep) {
      if (kDebugMode) {
        print('Downloading $count/$total ($countStep/$totalStep)');
      }
    }));
    final file = File('$distroPath/$filename.tar.gz');

    // Verify that the file exists and has > 2MB
    expect(await file.exists(), true);
    expect(await file.length(), greaterThan(2 * 1024 * 1024));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
