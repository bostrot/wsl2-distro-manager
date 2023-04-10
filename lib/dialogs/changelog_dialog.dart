import 'package:flutter_markdown/flutter_markdown.dart';
// ignore: depend_on_referenced_packages
import 'package:markdown/markdown.dart' as md;

import 'package:localization/localization.dart';
import 'package:wsl2distromanager/components/analytics.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:wsl2distromanager/components/helpers.dart';

/// Info Dialog
/// @param prefs: SharedPreferences
/// @param currentVersion: String
changelogDialog(prefs, currentVersion, body) {
  plausible.event(page: 'changelog');

  // Get root context by Key
  final context = GlobalVariable.infobox.currentContext!;

  showDialog(
    context: context,
    builder: (context) {
      return ContentDialog(
        constraints: const BoxConstraints(maxHeight: 500.0, maxWidth: 500.0),
        title: Text('🚀 ${'changelog-text'.i18n()} $currentVersion'),
        content: Markdown(
          shrinkWrap: true,
          data: body,
          extensionSet: md.ExtensionSet(
            md.ExtensionSet.gitHubFlavored.blockSyntaxes,
            [
              md.EmojiSyntax(),
              ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes
            ],
          ),
        ),
        actions: [
          Button(
              style: ButtonStyle(
                backgroundColor: ButtonState.all(Colors.blue),
                foregroundColor: ButtonState.all(Colors.white),
              ),
              onPressed: () {
                Navigator.pop(context);
              },
              child: Text('ok-text'.i18n())),
        ],
      );
    },
  );
}
