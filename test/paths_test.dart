import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/api/templates.dart';
import 'package:wsl2distromanager/components/constants.dart';
import 'dart:io';

void main() {
  test('Paths respect DistroPath preference', () async {
    SharedPreferences.setMockInitialValues({});
    await initPrefs();

    // Default behavior
    expect(getDistroPath().path, equals('${defaultPath}\\distros'));
    expect(Templates().getTemplatePath().path,
        equals('${defaultPath}\\templates'));

    // Change preference
    prefs.setString('DistroPath', 'D:\\CustomPath');

    // Check if paths updated
    expect(getDistroPath().path, equals('D:\\CustomPath\\distros'));
    expect(Templates().getTemplatePath().path,
        equals('D:\\CustomPath\\templates'));

    // Change DataPath
    prefs.setString('DataPath', 'C:\\DataPath');

    // Check if paths updated
    expect(getDistroPath().path,
        equals('D:\\CustomPath\\distros')); // Should stay same
    expect(Templates().getTemplatePath().path,
        equals('C:\\DataPath\\templates')); // Should update
    expect(getTmpPath().path, equals('C:\\DataPath\\tmp')); // Should update
  });

  test('getDataPath returns DataPath preference when set', () async {
    SharedPreferences.setMockInitialValues({'DataPath': 'C:\\MyData'});
    await initPrefs();
    expect(getDataPath().path, equals('C:\\MyData'));
  });

  test('getDataPath falls back to DistroPath when DataPath not set', () async {
    SharedPreferences.setMockInitialValues({'DistroPath': 'D:\\Fallback'});
    await initPrefs();
    expect(getDataPath().path, equals('D:\\Fallback'));
  });

  test('getDataPath falls back to defaultPath when neither pref is set',
      () async {
    SharedPreferences.setMockInitialValues({});
    await initPrefs();
    expect(getDataPath().path, equals(defaultPath));
  });

  test('getInstancePath uses per-instance pref when set', () async {
    final dir = Directory.systemTemp.createTempSync('instance_pref_');
    try {
      SharedPreferences.setMockInitialValues({'Path_myDistro': dir.path});
      await initPrefs();
      final result = getInstancePath('myDistro');
      expect(result.path, equals(dir.path));
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  // Note: the \\?\ prefix stripping only happens for live registry reads via
  // WslRegistry.getDistributionPath, which requires a real WSL environment and
  // cannot be tested without mocking native registry calls.

  test('getInstancePath falls back to distro subdir when no pref set',
      () async {
    SharedPreferences.setMockInitialValues({});
    await initPrefs();
    final result = getInstancePath('unknownDistro');
    // Should be under the distro base folder
    expect(result.path, equals('${defaultPath}\\unknownDistro'));
  });

  test('getWslConfigPath points to .wslconfig in user home', () async {
    SharedPreferences.setMockInitialValues({});
    await initPrefs();
    final configPath = getWslConfigPath();
    expect(configPath, endsWith('.wslconfig'));
    expect(configPath, contains(Platform.environment['USERNAME']!));
  });
}
