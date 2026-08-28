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

  /// `%s` / `%sN` are filled positionally by the localization package, so a
  /// translation that drops or invents one either loses the value it was meant
  /// to show or reads back a raw `%s` in the UI. `%s` and `%s0` are
  /// interchangeable for a single argument, so only the count has to match.
  test('every locale uses as many placeholders as English', () {
    final placeholder = RegExp(r'%s\d?');
    final english =
        json.decode(File('lib/i18n/en.json').readAsStringSync()) as Map;

    for (final locale in supportedLocalesList) {
      final file = File('lib/i18n/${locale.toString()}.json');
      final translated = json.decode(file.readAsStringSync()) as Map;

      for (final key in english.keys) {
        expect(placeholder.allMatches(translated[key] as String).length,
            placeholder.allMatches(english[key] as String).length,
            reason: '${file.path}: "$key" has the wrong placeholder count');
      }
    }
  });

  /// The keys the WSL documentation audit added for the `.wslconfig` and
  /// `wsl.conf` editors (see doc/audit/wsl-docs/). They were written with a
  /// real translation per locale rather than an English fallback, and the
  /// fallback is easy to reintroduce — scripts/add_translation_key.dart copies
  /// English into any locale that is missing a key — so it is worth pinning.
  group('WSL documentation audit i18n keys', () {
    const auditKeys = [
      'settingdefault-text',
      'settingunset-text',
      'defaultuserinfo-text',
      'wslconfrestart-text',
      'terminatedistro-text',
      'restartwslnow-text',
      'restartwslprompt-text',
      'deprecatedvalue-text',
      'onlyapplieswhen-text',
      'ignoredinmirrored-text',
      'milliseconds-text',
      'unitexample-text',
      'bootsystemd-text',
      'bootsystemdinfo-text',
      'bootcommand-text',
      'bootcommandinfo-text',
      'automountenabled-text',
      'automountenabledinfo-text',
      'automountmountfstab-text',
      'automountmountfstabinfo-text',
      'automountroot-text',
      'automountrootinfo-text',
      'automountoptions-text',
      'automountoptionsinfo-text',
      'networkgeneratehosts-text',
      'networkgeneratehostsinfo-text',
      'networkgenerateresolvconf-text',
      'networkgenerateresolvconfinfo-text',
      'networkhostname-text',
      'networkhostnameinfo-text',
      'interopenabled-text',
      'interopenabledinfo-text',
      'interopappendwindowspath-text',
      'interopappendwindowspathinfo-text',
      'gpu-text',
      'time-text',
      'user-text',
      'gpuenabled-text',
      'gpuenabledinfo-text',
      'usewindowstimezone-text',
      'usewindowstimezoneinfo-text',
      'protectbinfmt-text',
      'protectbinfmtinfo-text',
      'setdefaultdistro-text',
      'setwslversion-text',
      'microsoftwslsettings-text',
    ];

    test('are present and non-empty in every locale', () {
      for (final locale in supportedLocalesList) {
        final file = File('lib/i18n/${locale.toString()}.json');
        final translated = json.decode(file.readAsStringSync()) as Map;

        for (final key in auditKeys) {
          expect(translated[key], isA<String>(),
              reason: '${file.path} is missing "$key"');
          expect((translated[key] as String).trim(), isNotEmpty,
              reason: '${file.path}: "$key" is blank');
        }
      }
    });

    test('are translated, not copied from English', () {
      final english =
          json.decode(File('lib/i18n/en.json').readAsStringSync()) as Map;

      for (final locale in supportedLocalesList) {
        if (locale.toString() == 'en') continue;
        final file = File('lib/i18n/${locale.toString()}.json');
        final translated = json.decode(file.readAsStringSync()) as Map;

        for (final key in auditKeys) {
          // Short labels can legitimately be identical — "GPU" is "GPU"
          // everywhere. A sentence that matches English is a fallback.
          if ((english[key] as String).length <= 20) continue;
          expect(translated[key], isNot(english[key]),
              reason: '${file.path}: "$key" is still the English string');
        }
      }
    });
  });
}
