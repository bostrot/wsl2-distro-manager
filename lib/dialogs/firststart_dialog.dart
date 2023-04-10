import 'package:flutter_markdown/flutter_markdown.dart';
// ignore: depend_on_referenced_packages
import 'package:markdown/markdown.dart' as md;

import 'package:localization/localization.dart';
import 'package:wsl2distromanager/components/analytics.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/dialogs/info_dialog.dart';

/// First start Dialog
/// @param prefs: SharedPreferences
/// @param currentVersion: String
firststartDialog() {
  plausible.event(page: 'changelog');

  // Get root context by Key
  final context = GlobalVariable.infobox.currentContext!;
  const String title = "🎉 Welcome to WSL Manager! 🎉";
  const String body = """
Hi there! 👋

As the developer of this application, I want to express my sincere gratitude for choosing WSL Manager. 🙏 I have put in a lot of time and effort to make sure that this application is both intuitive and easy to use, while also providing a comprehensive set of features for managing your WSL environments.

Whether you're a developer, system administrator, or just someone who enjoys tinkering with Linux, I believe that WSL Manager will be a valuable addition to your toolkit. 🛠️

If you have any feedback or suggestions for improving the application, please don't hesitate to get in touch. I'm always eager to hear from users and to make WSL Manager even better. 📣

Thank you for your support, and happy WSL-ing!

Best regards,

Eric
""";
  showDialog(
    context: context,
    builder: (context) {
      return ContentDialog(
        constraints: const BoxConstraints(maxHeight: 500.0, maxWidth: 500.0),
        title: const Text(title),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              shareUsageData(prefs),
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
          )
        ],
      );
    },
  );
}
