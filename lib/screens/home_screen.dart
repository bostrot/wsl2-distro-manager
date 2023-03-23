import 'package:fluent_ui/fluent_ui.dart';
import 'package:localization/localization.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wsl2distromanager/components/analytics.dart';
import 'package:wsl2distromanager/components/notify.dart';

import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/components/constants.dart';
import 'package:wsl2distromanager/api/wsl.dart';
import 'package:wsl2distromanager/components/list.dart';

import 'dart:io';

import 'package:wsl2distromanager/theme.dart';

class HomePage extends StatefulWidget {
  const HomePage({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String status = '';
  bool loading = false;
  bool statusLeading = true;

  WSLApi api = WSLApi();

  void enableAnalytics() async {
    String platform = Platform.operatingSystemVersion;
    String exec = Platform.resolvedExecutable.toString();
    if (exec.contains("9891PhantomDevs.WSL2Manager")) {
      exec = "store";
    } else {
      exec = "git";
    }
    var tmpPlatform = platform;
    int? build;
    try {
      if (int.parse(platform.split('Build ')[1].split(')')[0]) >= 22000) {
        tmpPlatform = platform
            .replaceAll('Windows 10', 'Windows 11')
            .replaceAll('10.0', '11.0');
      }
      build = int.tryParse(platform.split('Build ')[1].split(')')[0]);
      if (build != null && build < 21354) {
        explorerPath = "\\\\wsl\$";
      }
    } catch (e) {
      // Empty path
    } finally {
      platform = tmpPlatform;
    }

    // Enable analytics
    plausible.event(name: 'Devices', props: {
      'app_source': exec,
      'app_version': currentVersion,
      'app_platform': platform,
      'app_locale': language,
      'app_theme': AppTheme.themeMode == ThemeMode.dark ? 'dark' : 'light',
    });
  }

  @override
  void initState() {
    super.initState();
    enableAnalytics();

    // Check updates
    App app = App();
    app.checkUpdate(currentVersion).then((updateUrl) {
      if (updateUrl != '') {
        statusMsg('',
            useWidget: true,
            widget: Row(
              children: [
                Text('newversion-text'.i18n()),
                TextButton(
                    onPressed: () => launchUrl(Uri.parse(updateUrl)),
                    child: Text('downloadnow-text'.i18n(),
                        style: const TextStyle(fontSize: 12.0))),
                Text('orcheck-text'.i18n()),
                TextButton(
                    onPressed: () => launchUrl(Uri.parse(windowsStoreUrl)),
                    child: Text('windowsstore-text'.i18n(),
                        style: const TextStyle(fontSize: 12.0))),
              ],
            ));
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

  Widget statusWidget = const Text('');
  void statusMsg(
    String msg, {
    bool loading = false,
    bool useWidget = false,
    bool leadingIcon = true,
    Widget widget = const Text(''),
  }) {
    if (!mounted) {
      return;
    }
    if (useWidget) {
      setState(() {
        status = 'WIDGET';
        this.loading = loading;
        statusWidget = widget;
        statusLeading = leadingIcon;
      });
    } else {
      setState(() {
        status = msg;
        this.loading = loading;
        statusLeading = leadingIcon;
      });
    }
  }

  Widget statusBuilder() {
    return AnimatedOpacity(
      opacity: status != '' ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 100),
      child: InfoBar(
        title: ListTile(
          title: status == 'WIDGET'
              ? statusWidget
              : Text(
                  status,
                  maxLines: 1,
                ),
          trailing: loading
              ? const SizedBox(width: 20.0, height: 20.0, child: ProgressRing())
              : const Text(''),
        ), // optional
        severity:
            InfoBarSeverity.info, // optional. Default to InfoBarSeverity.info
        onClose: () {
          // Dismiss the info bar
          setState(() {
            status = '';
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        DistroList(
          api: api,
        ),
        SizedBox(
          height: status != '' ? 80.0 : 0.0,
          child: Padding(
            padding:
                const EdgeInsets.only(bottom: 10.0, left: 10.0, right: 10.0),
            child: statusBuilder(),
          ),
        ),
      ],
    );
  }
}
