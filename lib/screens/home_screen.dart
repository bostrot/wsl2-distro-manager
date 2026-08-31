import 'package:fluent_ui/fluent_ui.dart';
import 'package:localization/localization.dart';
import 'package:wsl2distromanager/api/wsl.dart';
import 'package:wsl2distromanager/api/license_manager.dart';
import 'package:wsl2distromanager/components/analytics.dart';
import 'package:wsl2distromanager/components/ai_chat_panel.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/components/constants.dart';
import 'package:wsl2distromanager/components/list.dart';
import 'package:wsl2distromanager/components/recommendations_panel.dart';

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
  List<String> distroNames = [];

  /// One key for the life of the page. Re-created inline on every build, it
  /// tore down and rebuilt the whole list subtree — collapsing every expanded
  /// row and restarting the 5s poll — each time the AI panel toggled
  /// (audit LN-03).
  final GlobalKey<NavigatorState> _infoboxKey = GlobalKey<NavigatorState>();

  void enableAnalytics() async {
    String platform = Platform.operatingSystemVersion;
    String exec = 'unknown';
    try {
      exec = Platform.resolvedExecutable.toString();
      if (exec.contains("9891PhantomDevs.WSL2Manager")) {
        exec = "store";
      } else {
        exec = "git";
      }
    } catch (_) {
      exec = 'git';
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

    plausible.event(name: 'Devices', props: {
      'app_source': exec,
      'app_version': currentVersion,
      'app_platform': platform,
      'app_locale': language,
      'app_theme': AppTheme.themeMode == ThemeMode.dark ? 'dark' : 'light',
    });
  }

  Future<List<String>> _fetchDistroNames() async {
    try {
      final instances = await api.list(prefs.getBool('showDocker') ?? false);
      final list = instances.all;
      if (list.isNotEmpty && list[0] != 'wslNotInstalled') {
        return list;
      }
    } catch (_) {}
    return [];
  }

  @override
  void initState() {
    super.initState();
    enableAnalytics();
  }

  @override
  Widget build(BuildContext context) {
    final showAi = GlobalVariable.aiPanelVisible;
    bool isPro = false;
    try {
      isPro = GlobalVariable.testProEnabled || LicenseManager().isPro;
    } catch (_) {
      isPro = false;
    }

    return Stack(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            // A fixed 360px panel took 40% of a narrow window; below 1000px
            // it scales with the window instead (audit PS-38).
            final panelWidth = constraints.maxWidth < 1000
                ? (constraints.maxWidth * 0.36).roundToDouble()
                : 360.0;
            return SizedBox(
              height: constraints.maxHeight,
              width: constraints.maxWidth,
              child: Row(
                children: [
                  SizedBox(
                    width: showAi
                        ? constraints.maxWidth - panelWidth - 1
                        : constraints.maxWidth,
                    height: constraints.maxHeight,
                    child: Column(
                      key: (GlobalVariable.infobox = _infoboxKey),
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        FutureBuilder<List<String>>(
                          future: _fetchDistroNames(),
                          builder: (context, snapshot) {
                            final names = snapshot.data ?? [];
                            if (names.isNotEmpty && names != distroNames) {
                              distroNames = names;
                            }
                            return RecommendationsPanel(
                              key: const ValueKey('test-recommendations-panel'),
                              distroNames: distroNames,
                            );
                          },
                        ),
                        DistroList(api: api),
                      ],
                    ),
                  ),
                  if (showAi) ...[
                    Container(
                      width: 1,
                      color: surfaceBorderColor(context),
                    ),
                    SizedBox(
                      width: panelWidth,
                      height: constraints.maxHeight,
                      child: AiChatPanel(
                        // The panel's own close control — the FAB behind it
                        // used to be the only way out (PS-34).
                        onClose: () => setState(
                            () => GlobalVariable.aiPanelVisible = false),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
        if (isPro)
          Positioned(
            // 16px past the panel's live width (PS-38 made it responsive).
            right: showAi
                ? ((MediaQuery.of(context).size.width < 1000
                        ? (MediaQuery.of(context).size.width * 0.36)
                            .roundToDouble()
                        : 360.0) +
                    16)
                : 16,
            bottom: 16,
            // A Button rather than a GestureDetector: this is the only entry
            // point to the AI chat panel and a GestureDetector has no focus
            // node, so a keyboard could not reach it at all (audit IA-04).
            child: MergeSemantics(
              child: Tooltip(
                message: 'ai-assistant-title'.i18n(),
                child: Button(
                  key: const ValueKey('test-ai-chat-toggle'),
                  onPressed: () {
                    setState(() {
                      GlobalVariable.aiPanelVisible =
                          !GlobalVariable.aiPanelVisible;
                    });
                  },
                  // Accent-filled in both states. The closed state used to be
                  // a grey wash over the page — 1.25:1 in light, 1.02:1 in
                  // dark — so the only entry point to the AI panel was close
                  // to invisible in both themes (audit TL-06, PS-14, LN-24).
                  style: ButtonStyle(
                    padding: const WidgetStatePropertyAll(EdgeInsets.zero),
                    backgroundColor: WidgetStatePropertyAll(
                        FluentTheme.of(context).accentColor),
                    shape: WidgetStatePropertyAll(CircleBorder(
                      side: BorderSide(
                        color: FluentTheme.of(context).accentColor.darker,
                        width: 1,
                      ),
                    )),
                  ),
                  child: const SizedBox.square(
                    dimension: 48,
                    child: Icon(
                      FluentIcons.chat,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
