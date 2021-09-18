import 'package:desktop_window/desktop_window.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:system_theme/system_theme.dart';

import 'api.dart';
import 'distro_list_component.dart';
import 'distro_create_component.dart';

void main() {
  runApp(const MyApp());
  DesktopWindow.setWindowSize(const Size(650, 500));
  DesktopWindow.setMinWindowSize(const Size(650, 500));
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return FluentApp(
      title: 'WSL2 Distro Manager by Bostrot',
      theme: ThemeData(
        accentColor: SystemTheme.accentInstance.accent.toAccentColor(),
        brightness: Brightness.light, // or Brightness.dark
      ),
      home: const MyHomePage(title: 'WSL2 Distro Manager by Bostrot'),
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

  WSLApi api = WSLApi();

  void statusMsg(msg) {
    setState(() {
      status = msg;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      content: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            createComponent(api, statusMsg),
            Padding(
              padding: const EdgeInsets.only(left: 30.0, right: 30.0, top: 14.0, bottom: 8.0),
              child: Builder(
                builder: (ctx) {
                  if (status != '') {
                    return Container(
                      color: const Color.fromRGBO(0, 0, 0, 0.05),
                      child: ListTile(
                        title: Text(status),
                        leading: const Icon(FluentIcons.info),
                        trailing: IconButton(icon: const Icon(FluentIcons.close), onPressed: () {
                            setState(() {
                              status = '';
                            });
                          }),
                      )
                    );
                  } else {
                    return const Text('');
                  }
                },
              ),
            ),
            distroList(api, statusMsg),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(onPressed: () async {
                  await canLaunch('https://bostrot.com') ? 
                  await launch('https://bostrot.com') : throw 'Could not launch URL';
                  }, child: const Text("Created by Bostrot", style: TextStyle(fontSize: 12.0))),
                const Text('|', style: TextStyle(fontSize: 12.0)),
                TextButton(onPressed: () async {
                  await canLaunch('https://github.com/bostrot/wsl2-distro-manager') ? 
                  await launch('https://github.com/bostrot/wsl2-distro-manager') : throw 'Could not launch URL';
                  }, child: const Text("Visit GitHub", style: TextStyle(fontSize: 12.0))),
                const Text('|', style: TextStyle(fontSize: 12.0)),
                TextButton(onPressed: () async {
                  await canLaunch('http://paypal.me/bostrot') ? 
                  await launch('http://paypal.me/bostrot') : throw 'Could not launch URL';
                  }, child: const Text("Donate", style: TextStyle(fontSize: 12.0))),
              ],
            )
          ],
        ),
      ),
    );
  }
}
