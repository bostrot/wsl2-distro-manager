import 'package:fluent_ui/fluent_ui.dart';

import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/components/constants.dart';
import 'package:wsl2distromanager/components/api.dart';
import 'package:wsl2distromanager/components/list.dart';
import 'package:wsl2distromanager/components/navbar.dart';
import 'package:wsl2distromanager/dialogs/create_dialog.dart';
import 'package:wsl2distromanager/dialogs/info_dialog.dart';
import 'package:wsl2distromanager/screens/settings_screen.dart';

import 'package:wsl2distromanager/components/sync.dart';

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, required this.title, required this.themeData})
      : super(key: key);

  final String title;
  final ThemeData themeData;

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

    Sync().startServer('ITS2');

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
                    onPressed: () => launchURL(updateUrl),
                    child: const Text("Download now",
                        style: TextStyle(fontSize: 12.0))),
                const Text('or check the'),
                TextButton(
                    onPressed: () => launchURL(windowsStoreUrl),
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
            title: const Text('About this app'),
            onTap: () {
              infoDialog(context, prefs, statusMsg, currentVersion);
            },
          ),
          PaneItemAction(
            icon: const Icon(FluentIcons.settings),
            title: const Text('Settings'),
            onTap: () {
              Navigator.push(
                  context,
                  FluentPageRoute(
                      builder: (context) => SettingsPage(
                            themeData: widget.themeData,
                          )));
            },
          ),
          PaneItemAction(
            icon: const Icon(FluentIcons.add),
            title: const Text('Add an instance'),
            onTap: () {
              createDialog(context, statusMsg);
            },
          ),
        ],
      ),
      content: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          navbar(widget.themeData),
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
