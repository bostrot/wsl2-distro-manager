//import 'package:desktop_window/desktop_window.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:system_theme/system_theme.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:wsl2distromanager/components/api.dart';
import 'package:wsl2distromanager/components/analytics.dart';
import 'package:wsl2distromanager/components/list.dart';
import 'package:wsl2distromanager/dialogs/create_dialog.dart';
import 'package:wsl2distromanager/dialogs/info_dialog.dart';

// TODO: Update on release
const String currentVersion = "v0.6.1";
const String windowsStoreUrl = "https://www.microsoft.com/store/"
    "productId/9NWS9K95NMJB";

late SharedPreferences prefs;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemTheme.accentInstance.load();
  runApp(const MyApp());
  doWhenWindowReady(() {
    final win = appWindow;
    const initialSize = Size(650, 500);
    win.minSize = initialSize;
    win.size = initialSize;
    win.alignment = Alignment.center;
    win.title = "WSL Distro Manager";
    win.show();
  });

  prefs = await SharedPreferences.getInstance();
  bool? privacyMode = prefs.getBool('privacyMode');
  if (privacyMode != null && privacyMode) {
    plausible.enabled = false;
  }

  // Enable analytics
  plausible.event();
}

ThemeData themeData = ThemeData();

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: SystemTheme.darkMode,
      builder: (BuildContext context, AsyncSnapshot<bool> darkMode) {
        if (darkMode.hasData) {
          if (darkMode.data == false) {
            // lightmode
            themeData = ThemeData(
              /*scaffoldBackgroundColor: const Color.fromRGBO(243, 243, 243, 1.0),*/
              activeColor: Colors.black,
              accentColor: SystemTheme.accentInstance.accent.toAccentColor(),
              brightness: Brightness.light, // or Brightness.dark
            );
          } else {
            // darkmode
            themeData = ThemeData(
              /*scaffoldBackgroundColor: const Color.fromRGBO(243, 243, 243, 1.0),*/
              activeColor: Colors.white,
              accentColor: SystemTheme.accentInstance.accent.toAccentColor(),
              brightness: Brightness.dark, // or Brightness.dark
            );
          }
          return FluentApp(
            title: 'WSL2 Distro Manager by Bostrot',
            theme: themeData,
            home: const MyHomePage(title: 'WSL Distro Manager by Bostrot'),
            debugShowCheckedModeBanner: false,
          );
        } else if (darkMode.hasError) {
          return const FluentApp(
            home: Center(child: Text('An error occured. Please report this.')),
          );
        } else {
          return const FluentApp(home: Text(''));
        }
      },
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  String status = '';
  bool loading = false;
  bool statusLeading = true;

  WSLApi api = WSLApi();

  @override
  void initState() {
    super.initState();

    // Check updates
    App app = App();
    app.checkUpdate(currentVersion).then((updateUrl) {
      if (updateUrl != '') {
        statusMsg('',
            useWidget: true,
            widget: Row(
              children: [
                const Text('A new version is available'),
                TextButton(
                    onPressed: () async {
                      await canLaunch(updateUrl)
                          ? await launch(updateUrl)
                          : throw 'Could not launch URL';
                    },
                    child: const Text("Download now",
                        style: TextStyle(fontSize: 12.0))),
                const Text('or check the'),
                TextButton(
                    onPressed: () async {
                      await canLaunch(windowsStoreUrl)
                          ? await launch(windowsStoreUrl)
                          : throw 'Could not launch URL';
                    },
                    child: const Text("Windows Store",
                        style: TextStyle(fontSize: 12.0))),
              ],
            ));
      }
    });

    // Check motd
    app.checkMotd().then((String motd) {
      statusMsg(motd, leadingIcon: false);
    });
  }

  Widget statusWidget = const Text('');
  void statusMsg(
    String msg, {
    bool loading = false,
    bool useWidget = false,
    bool leadingIcon = true,
    Widget widget = const Text(''),
  }) {
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
      child: Padding(
        padding: const EdgeInsets.only(top: 8.0),
        child: Container(
            color: const Color.fromRGBO(0, 0, 0, 0.2),
            child: ListTile(
              title: status == 'WIDGET' ? statusWidget : Text(status),
              leading:
                  statusLeading ? const Icon(FluentIcons.info) : const Text(''),
              trailing: loading
                  ? const SizedBox(
                      child: ProgressRing(), width: 20.0, height: 20.0)
                  : IconButton(
                      icon: const Icon(FluentIcons.close),
                      onPressed: () {
                        setState(() {
                          status = '';
                        });
                      }),
            )),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return NavigationView(
      pane: NavigationPane(
        items: [
          PaneItemAction(
            icon: const Icon(FluentIcons.info),
            onTap: () {
              infoDialog(context, prefs, statusMsg, currentVersion);
            },
            title: const Text('About this app'),
          ),
          PaneItem(
            icon: const Icon(FluentIcons.settings),
            title: const Text('Settings'),
          ),
          PaneItemAction(
            icon: const Icon(FluentIcons.add),
            onTap: () {
              createDialog(context, api, statusMsg);
            },
            title: const Text('Add an instance'),
          ),
        ],
      ),
      content: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(4.0),
            child: WindowTitleBarBox(
              child: Row(
                children: [
                  Expanded(
                    child: MoveWindow(
                      child: const Padding(
                        padding: EdgeInsets.only(left: 20.0, top: 8.0),
                        child: Text('WSL Manager ' + currentVersion),
                      ),
                    ),
                  ),
                  MinimizeWindowButton(
                    colors:
                        WindowButtonColors(iconNormal: themeData.activeColor),
                  ),
                  MaximizeWindowButton(
                    colors:
                        WindowButtonColors(iconNormal: themeData.activeColor),
                  ),
                  CloseWindowButton(
                    colors: WindowButtonColors(
                        iconNormal: themeData.activeColor,
                        mouseOver: Colors.warningPrimaryColor),
                  )
                ],
              ),
            ),
          ),
          DistroList(
            api: api,
            statusMsg: statusMsg,
          ),
          Padding(
            padding: const EdgeInsets.all(15.0),
            child: statusBuilder(),
          ),
        ],
      ),
    );
  }
}
