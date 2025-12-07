import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/api/templates.dart';
import 'package:wsl2distromanager/components/constants.dart';

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
}
