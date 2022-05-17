import 'package:fluent_ui/fluent_ui.dart';
import 'package:localization/localization.dart';

import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/components/constants.dart';
import 'package:wsl2distromanager/components/api.dart';
import 'package:wsl2distromanager/components/list.dart';
import 'package:wsl2distromanager/components/navbar.dart';
import 'package:wsl2distromanager/components/theme.dart';
import 'package:wsl2distromanager/dialogs/create_dialog.dart';
import 'package:wsl2distromanager/dialogs/info_dialog.dart';
import 'package:wsl2distromanager/screens/actions_screen.dart';
import 'package:wsl2distromanager/screens/settings_screen.dart';

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
                    onPressed: () => launchURL(updateUrl),
                    child: Text('downloadnow-text'.i18n(),
                        style: const TextStyle(fontSize: 12.0))),
                Text('orcheck-text'.i18n()),
                TextButton(
                    onPressed: () => launchURL(windowsStoreUrl),
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
    ScrollController scrollController = ScrollController();
    return AnimatedOpacity(
      opacity: status != '' ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 100),
      child: Padding(
        padding: const EdgeInsets.only(top: 8.0),
        child: Container(
            decoration: BoxDecoration(
              color: themeData.activeColor.withOpacity(0.05),
              borderRadius: const BorderRadius.all(Radius.circular(8.0)),
            ),
            child: ListTile(
              title: SingleChildScrollView(
                  controller: scrollController,
                  child: status == 'WIDGET'
                      ? statusWidget
                      : Text(
                          status,
                          maxLines: 1,
                        )),
              leading:
                  statusLeading ? const Icon(FluentIcons.info) : const Text(''),
              trailing: loading
                  ? const SizedBox(
                      child: ProgressRing(), width: 20.0, height: 20.0)
                  : IconButton(
                      icon: const Icon(FluentIcons.chrome_close),
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
        displayMode: PaneDisplayMode.auto,
        items: [
          PaneItemAction(
            icon: const Icon(FluentIcons.info),
            title: Text('about-text'.i18n()),
            onTap: () {
              infoDialog(context, prefs, statusMsg, currentVersion);
            },
          ),
          PaneItemAction(
            icon: const Icon(FluentIcons.settings),
            title: Text('settings-text'.i18n()),
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
            icon: const Icon(FluentIcons.settings_add),
            title: Text('managequickactions-text'.i18n()),
            onTap: () {
              Navigator.push(
                  context,
                  FluentPageRoute(
                      builder: (context) => QuickPage(
                            themeData: widget.themeData,
                          )));
            },
          ),
          PaneItemAction(
            icon: const Icon(FluentIcons.add),
            title: Text('addinstance-text'.i18n()),
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
            padding: const EdgeInsets.all(10.0),
            child: statusBuilder(),
          ),
        ],
      ),
    );
  }
}
