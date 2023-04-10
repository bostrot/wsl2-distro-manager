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
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/components/notify.dart';

void main() {
  void statusMsg(
    String msg, {
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

  // test('CRC32 combination', () {
  //   // Bzip2CombinedCrc _fileCrc = Bzip2CombinedCrc();

  //   var testCrc1 = 3957769958;
  //   var testCrc2 = 3028153490;

  //   // _fileCrc.update(testCrc1);
  //   // _fileCrc.update(testCrc2);
  //   var length = "How are you today?".length;
  //   var combinedCrc = CRC32().combine(testCrc1, testCrc2, length);

  //   expect(combinedCrc, 1463772643);
  // });

  test('Docker rootfs download single layer', () async {
    const String image = 'library/alpine';
    const String tag = 'latest';
    const String distroPath = 'C:/WSL2-Distros/distros';
    final String filename = DockerImage().filename(image, tag);
    // Get rootfs
    await DockerImage().getRootfs("test", image, tag: tag,
        progress: ((count, total, countStep, totalStep) {
      if (kDebugMode) {
        print('Downloading $count/$total ($countStep/$totalStep)');
      }
    }));
    final file = File('$distroPath/$filename.tar.gz');

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
