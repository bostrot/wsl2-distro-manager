import 'package:desktop_window/desktop_window.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:system_theme/system_theme.dart';

import 'api.dart';
import 'distro_list_component.dart';
import 'distro_create_component.dart';

String currentVersion = "v0.5.1";

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemTheme.accentInstance.load();
  runApp(const MyApp());
  DesktopWindow.setWindowSize(const Size(650, 500));
  DesktopWindow.setMinWindowSize(const Size(650, 500));
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: SystemTheme.darkMode,
      builder: (BuildContext context, AsyncSnapshot<bool> darkMode) {
        if (darkMode.hasData) {
          ThemeData theme;
          if (darkMode.data == false) {
            // lightmode
            theme = ThemeData(
              /*scaffoldBackgroundColor: const Color.fromRGBO(243, 243, 243, 1.0),*/
              accentColor: SystemTheme.accentInstance.accent.toAccentColor(),
              brightness: Brightness.light, // or Brightness.dark
            );
          } else {
            // darkmode
            theme = ThemeData(
              /*scaffoldBackgroundColor: const Color.fromRGBO(243, 243, 243, 1.0),*/
              accentColor: SystemTheme.accentInstance.accent.toAccentColor(),
              brightness: Brightness.dark, // or Brightness.dark
            );
          }
          return FluentApp(
            title: 'WSL2 Distro Manager by Bostrot',
            theme: theme,
            home: const MyHomePage(title: 'WSL2 Distro Manager by Bostrot'),
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
                        style: TextStyle(fontSize: 12.0)))
              ],
            ));
      }
    });

    // Check motd
    app.checkMotd().then((String motd) {
      print(motd);
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
    return ScaffoldPage(
      padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
      content: Padding(
        padding: const EdgeInsets.only(left: 8.0, right: 8.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            createComponent(api, statusMsg),
            DistroList(
              api: api,
              statusMsg: statusMsg,
            ),
            statusBuilder(),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                    onPressed: () async {
                      await canLaunch('https://bostrot.com')
                          ? await launch('https://bostrot.com')
                          : throw 'Could not launch URL';
                    },
                    child: const Text("Created by Bostrot",
                        style: TextStyle(fontSize: 12.0))),
                const Text('|', style: TextStyle(fontSize: 12.0)),
                TextButton(
                    onPressed: () async {
                      await canLaunch(
                              'https://github.com/bostrot/wsl2-distro-manager')
                          ? await launch(
                              'https://github.com/bostrot/wsl2-distro-manager')
                          : throw 'Could not launch URL';
                    },
                    child: const Text("Visit GitHub",
                        style: TextStyle(fontSize: 12.0))),
                const Text('|', style: TextStyle(fontSize: 12.0)),
                TextButton(
                    onPressed: () async {
                      await canLaunch('http://paypal.me/bostrot')
                          ? await launch('http://paypal.me/bostrot')
                          : throw 'Could not launch URL';
                    },
                    child:
                        const Text("Donate", style: TextStyle(fontSize: 12.0))),
              ],
            )
          ],
        ),
      ),
    );
  }
}
