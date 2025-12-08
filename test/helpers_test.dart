import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wsl2distromanager/components/helpers.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'DistroName_test': 'Test Distro',
    });
    prefs = await SharedPreferences.getInstance();
  });

  test('distroLabel returns correct label', () {
    expect(distroLabel('test'), 'Test Distro');
    expect(distroLabel('unknown'), 'unknown');
  });

  test('replaceSpecialChars replaces non-alphanumeric characters', () {
    expect(replaceSpecialChars('test-distro'), 'test_distro');
    expect(replaceSpecialChars('test/distro'), 'test_distro');
    expect(replaceSpecialChars('test distro'), 'test_distro');
    expect(replaceSpecialChars('test123distro'), 'test123distro');
  });

  test('tryDecodeJson decodes valid JSON', () {
    expect(tryDecodeJson('{"key": "value"}'), {'key': 'value'});
    expect(tryDecodeJson('[1, 2, 3]'), [1, 2, 3]);
  });

  test('tryDecodeJson returns null for invalid JSON', () {
    expect(tryDecodeJson('{invalid}'), null);
    expect(tryDecodeJson(''), null);
  });

  test('fixJsonContent fixes JSON with extra characters', () {
    expect(fixJsonContent('{"key": "value"}'), '{"key": "value"}');
    expect(fixJsonContent(' {"key": "value"} '), '{"key": "value"}');
    // Assuming fixJsonContent logic handles these cases based on implementation
    // It tries removing first/last char if decode fails
    expect(fixJsonContent('x{"key": "value"}'), '{"key": "value"}');
    expect(fixJsonContent('{"key": "value"}x'), '{"key": "value"}');
  });
}
