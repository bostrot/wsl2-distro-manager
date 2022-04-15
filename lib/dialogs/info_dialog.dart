import 'package:wsl2distromanager/components/analytics.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'base_dialog.dart';

/// Rename Dialog
/// @param context: context
/// @param statusMsg: Function(String, {bool loading})
infoDialog(context, prefs, Function(String, {bool loading}) statusMsg,
    currentVersion) {
  plausible.event(page: 'info');

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
                  const ClickableUrl(
                    clickEvent: "url_clicked",
                    url: 'https://bostrot.com',
                    text: "Created by Bostrot",
                  ),
                  const ClickableUrl(
                      clickEvent: "git_clicked",
                      url: "https://github.com/bostrot/wsl2-distro-manager",
                      text: "Visit GitHub"),
                  const ClickableUrl(
                      clickEvent: "changelog_clicked",
                      url: "https://github.com/bostrot/wsl2-distro-manager/"
                          "releases",
                      text: "Changelog"),
                  const ClickableUrl(
                      clickEvent: "donate_clicked",
                      url: "https://paypal.me/bostrot",
                      text: "Donate"),
                  ClickableText(
                      clickEvent: "libraries_clicked",
                      onPressed: () {
                        dialog(
                          context: context,
                          item: "Dependencies",
                          statusMsg: statusMsg,
                          title: 'Dependencies',
                          body: "",
                          bodyIsWidget: true,
                          bodyAsWidget: const DependencyList(),
                          submitInput: false,
                          centerText: true,
                        );
                      },
                      text: "Dependencies"),
                  ClickableText(
                      clickEvent: "analytics_clicked",
                      onPressed: () {
                        bool privacyMode =
                            prefs.getBool('privacyMode') ?? false;
                        String privacyStatus = privacyMode
                            ? "\"NOT sharing anonymous usage data\""
                            : "\"Sharing anonymous usage data\"";
                        dialog(
                            context: context,
                            item: "Allow",
                            statusMsg: statusMsg,
                            title: 'Usage Data',
                            body:
                                'Do you want to share anonymous usage data to '
                                'improve this app? This is done via plausible '
                                'a privacy-friendly and open source analytics '
                                'tool.\n\n'
                                'Current status: $privacyStatus',
                            submitText: 'Do NOT share',
                            submitInput: false,
                            submitStyle: const ButtonStyle(),
                            cancelText: 'Share',
                            onCancel: () {
                              plausible.event(name: "privacy_off");
                              prefs.setBool('privacyMode', false);
                              plausible.enabled = true;
                            },
                            onSubmit: (inputText) {
                              plausible.event(name: "privacy_on");
                              prefs.setBool('privacyMode', true);
                              plausible.enabled = false;
                              statusMsg('Privacy mode enabled.');
                            });
                      },
                      text: "Privacy"),
                ],
              ),
            ),
          ),
          actions: [
            Button(
                child: const Text('OK'),
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
      children: const [
        ClickableDependency(name: "desktop_window"),
        ClickableDependency(name: "fluent_ui"),
        ClickableDependency(name: "system_theme"),
        ClickableDependency(name: "file_picker"),
        ClickableDependency(name: "url_launcher"),
        ClickableDependency(name: "dio"),
        ClickableDependency(name: "package_info_plus"),
        ClickableDependency(name: "bitsdojo_window"),
        ClickableDependency(name: "plausible_analytics"),
        ClickableDependency(name: "shared_preferences"),
        ClickableDependency(name: "shelf_static"),
      ],
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
              onPressed: () async {
                await canLaunch("https://pub.dev/packages/$name")
                    ? await launch("https://pub.dev/packages/$name")
                    : null;
              },
              child: Text(name)),
          TextButton(
              onPressed: () async {
                await canLaunch("https://pub.dev/packages/$name/license")
                    ? await launch("https://pub.dev/packages/$name/license")
                    : null;
              },
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
            await canLaunch(url) ? await launch(url) : null;
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
