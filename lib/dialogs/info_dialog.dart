import 'package:wsl2distromanager/components/api.dart';
import 'package:wsl2distromanager/components/analytics.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'base_dialog.dart';

/// Rename Dialog
/// @param context: context
/// @param api: WSLApi
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                TextButton(
                    onPressed: () async {
                      plausible.event(name: "url_clicked");
                      await canLaunch('https://bostrot.com')
                          ? await launch('https://bostrot.com')
                          : throw 'Could not launch URL';
                    },
                    child: const Text(
                      "Created by Bostrot",
                    )),
                TextButton(
                    onPressed: () async {
                      plausible.event(name: "git_clicked");
                      await canLaunch(
                              'https://github.com/bostrot/wsl2-distro-manager')
                          ? await launch(
                              'https://github.com/bostrot/wsl2-distro-manager')
                          : throw 'Could not launch URL';
                    },
                    child: const Text(
                      "Visit GitHub",
                    )),
                TextButton(
                    onPressed: () async {
                      plausible.event(name: "donate_clicked");
                      await canLaunch('http://paypal.me/bostrot')
                          ? await launch('http://paypal.me/bostrot')
                          : throw 'Could not launch URL';
                    },
                    child: const Text(
                      "Donate",
                    )),
                TextButton(
                    onPressed: () {
                      plausible.event(name: "analytics_clicked");
                      dialog(
                          context: context,
                          item: "Allow",
                          api: WSLApi(),
                          statusMsg: statusMsg,
                          title: 'Usage Data',
                          body: 'Do you want to share anonymous usage data to '
                              'improve this app?',
                          submitText: 'Enable privacy mode',
                          submitInput: false,
                          submitStyle: const ButtonStyle(),
                          cancelText: 'Share usage data',
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
                    child: const Text(
                      "Privacy",
                    )),
              ],
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
