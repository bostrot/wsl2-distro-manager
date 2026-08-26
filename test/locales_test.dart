import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wsl2distromanager/components/constants.dart';

/// A locale without a matching lib/i18n file makes LocalJsonLocalization throw
/// during load, and the failed delegate leaves the app rendering an empty
/// window — so the two lists have to stay in step.
void main() {
  test('every supported locale has a translation file named after it', () {
    for (final locale in supportedLocalesList) {
      final file = File('lib/i18n/${locale.toString()}.json');
      expect(file.existsSync(), true,
          reason: 'missing ${file.path} for locale $locale');
    }
  });

  test('every language option resolves to a shipped translation', () {
    for (final code in languageOptions.keys) {
      expect(File('lib/i18n/$code.json').existsSync(), true,
          reason: 'language option "$code" has no lib/i18n/$code.json');
    }
  });

  test('every translation file is reachable from the supported locales', () {
    final shipped = Directory('lib/i18n')
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .where((name) => name.endsWith('.json'))
        .map((name) => name.substring(0, name.length - '.json'.length))
        .toSet();
    final supported =
        supportedLocalesList.map((locale) => locale.toString()).toSet();

    expect(shipped.difference(supported), isEmpty,
        reason: 'translation files nothing can select');
  });

  test('all translation files parse and share the English key set', () {
    final english =
        (json.decode(File('lib/i18n/en.json').readAsStringSync()) as Map)
            .keys
            .toSet();

    for (final locale in supportedLocalesList) {
      final file = File('lib/i18n/${locale.toString()}.json');
      final keys = (json.decode(file.readAsStringSync()) as Map).keys.toSet();
      expect(english.difference(keys), isEmpty,
          reason: '${file.path} is missing keys');
    }
  });
}
