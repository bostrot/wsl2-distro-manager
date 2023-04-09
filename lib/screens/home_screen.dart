import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
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
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      key: GlobalVariable.infobox,
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        DistroList(
          api: api,
        ),
      ],
    );
  }
}
