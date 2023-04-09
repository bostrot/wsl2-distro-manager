import 'package:localization/localization.dart';
import 'package:wsl2distromanager/components/analytics.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/components/notify.dart';
import 'package:wsl2distromanager/oss_licenses.dart';
import 'base_dialog.dart';

/// Rename Dialog
/// @param context: context
infoDialog(prefs, currentVersion) {
  plausible.event(page: 'info');

  // Get root context by Key
  final context = GlobalVariable.root.currentContext!;

  showDialog(
      context: context,
      builder: (context) {
        return ContentDialog(
          title: Center(child: Text('WSL Manager $currentVersion')),
          content: SizedBox(
            width: 400.0,
            height: 200.0,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ClickableUrl(
                    clickEvent: "url_clicked",
                    url: 'https://bostrot.com',
                    text: 'createdby-text'.i18n(),
                  ),
                  ClickableUrl(
                      clickEvent: "git_clicked",
                      url: "https://github.com/bostrot/wsl2-distro-manager",
                      text: 'visitgithub-text'.i18n()),
                  ClickableUrl(
                      clickEvent: "changelog_clicked",
                      url: "https://github.com/bostrot/wsl2-distro-manager/"
                          "releases",
                      text: 'changelog-text'.i18n()),
                  ClickableUrl(
                      clickEvent: "donate_clicked",
                      url: "https://paypal.me/bostrot",
                      text: 'donate-text'.i18n()),
                  ClickableText(
                    clickEvent: "libraries_clicked",
                    onPressed: () {
                      dialog(
                        context: context,
                        item: 'dependencies-text'.i18n(),
                        title: 'dependencies-text'.i18n(),
                        body: "",
                        bodyIsWidget: true,
                        bodyAsWidget: const DependencyList(),
                        submitInput: false,
                        centerText: true,
                      );
                    },
                    text: 'dependencies-text'.i18n(),
                  ),
                  ClickableText(
                      clickEvent: "analytics_clicked",
                      onPressed: () {
                        bool privacyMode =
                            prefs.getBool('privacyMode') ?? false;
                        String privacyStatus = privacyMode
                            ? 'notsharingdata-text'.i18n()
                            : 'sharingdata-text'.i18n();
                        dialog(
                            context: context,
                            item: 'allow-text'.i18n(),
                            title: 'usagedata-text'.i18n(),
                            body: 'usagedatawarning-text'.i18n([privacyStatus]),
                            submitText: 'donotshare-text'.i18n(),
                            submitInput: false,
                            submitStyle: const ButtonStyle(),
                            cancelText: 'share-text'.i18n(),
                            onCancel: () {
                              plausible.event(name: "privacy_off");
                              prefs.setBool('privacyMode', false);
                              plausible.enabled = true;
                            },
                            onSubmit: (inputText) {
                              plausible.event(name: "privacy_on");
                              prefs.setBool('privacyMode', true);
                              plausible.enabled = false;
                              Notify.message('privacymodeenabled-text'.i18n());
                            });
                      },
                      text: 'privacy-text'.i18n()),
                ],
              ),
            ),
          ),
          actions: [
            Button(
                child: Text('ok-text'.i18n()),
                onPressed: () {
                  Navigator.pop(context);
                }),
          ],
        );
      });
}

class DependencyList extends StatelessWidget {
  const DependencyList({
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: ossLicenses.asMap().entries.map((entry) {
        return ClickableText(
          clickEvent: "license_clicked",
          onPressed: () {
            dialog(
              context: context,
              item: entry.value.name,
              title: entry.value.name,
              body: entry.value.license ?? 'No License',
              submitInput: false,
              centerText: true,
            );
          },
          text: entry.value.name,
        );
      }).toList(),
    );
  }
}

class ClickableDependency extends StatelessWidget {
  const ClickableDependency({Key? key, required this.name}) : super(key: key);

  final String name;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextButton(
              onPressed: () =>
                  launchUrl(Uri.parse("https://pub.dev/packages/$name")),
              child: Text(name)),
          TextButton(
              onPressed: () => launchUrl(
                  Uri.parse("https://pub.dev/packages/$name/license")),
              child: const Text("(LICENSE)")),
        ],
      ),
    );
  }
}

class ClickableUrl extends StatelessWidget {
  const ClickableUrl(
      {Key? key,
      required this.clickEvent,
      required this.url,
      required this.text})
      : super(key: key);

  final String clickEvent;
  final String url;
  final String text;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: TextButton(
          onPressed: () async {
            plausible.event(name: clickEvent);
            launchUrl(Uri.parse(url));
          },
          child: Text(text)),
    );
  }
}

class ClickableText extends StatelessWidget {
  const ClickableText(
      {Key? key,
      required this.clickEvent,
      required this.onPressed,
      required this.text})
      : super(key: key);

  final String clickEvent;
  final Function() onPressed;
  final String text;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: TextButton(onPressed: onPressed, child: Text(text)),
    );
  }
}
