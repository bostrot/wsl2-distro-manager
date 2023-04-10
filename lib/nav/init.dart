import 'package:fluent_ui/fluent_ui.dart' hide Page;
import 'package:flutter/gestures.dart';
import 'package:localization/localization.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wsl2distromanager/api/wsl.dart';
import 'package:wsl2distromanager/components/constants.dart';
import 'package:wsl2distromanager/components/notify.dart';

initRoot(statusMsg) {
  // Check updates
  App app = App();
  app.checkUpdate(currentVersion).then((updateUrl) {
    if (updateUrl != '') {
      statusMsg('',
          useWidget: true,
          widget: RichText(
              text: TextSpan(children: [
            TextSpan(
                text: '${'newversion-text'.i18n()} ',
                style: const TextStyle(fontSize: 14.0)),
            TextSpan(
                text: '${'downloadnow-text'.i18n()} ',
                style: TextStyle(
                    color: Colors.purple,
                    fontSize: 14.0,
                    fontWeight: FontWeight.bold),
                recognizer: TapGestureRecognizer()
                  ..onTap = () => launchUrl(Uri.parse(updateUrl))),
            TextSpan(
                text: '${'orcheck-text'.i18n()} ',
                style: const TextStyle(fontSize: 14.0)),
            TextSpan(
                text: '${'windowsstore-text'.i18n()} ',
                style: TextStyle(
                    color: Colors.purple,
                    fontSize: 14.0,
                    fontWeight: FontWeight.bold),
                recognizer: TapGestureRecognizer()
                  ..onTap = () => launchUrl(Uri.parse(windowsStoreUrl))),
          ])));
    }
  });

  // Check motd
  app.checkMotd().then((String motd) {
    statusMsg(motd, leadingIcon: false);
  });

  // Call constructor to initialize
  Notify();
  Notify.message = statusMsg;
}
