import 'package:localization/localization.dart';
import 'package:wsl2distromanager/components/analytics.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:wsl2distromanager/components/api.dart';
import 'package:wsl2distromanager/components/console.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/components/sync.dart';
import 'package:wsl2distromanager/components/theme.dart';
import 'package:wsl2distromanager/dialogs/sync_dialog.dart';

String extractPorts(String portRaw) {
  List<String> portsRaw = portRaw.split('\n');
  String ports = '';
  for (String portRaw in portsRaw) {
    if (portRaw.contains(':')) {
      if (ports != '') {
        ports += ', ';
      }
      ports += int.tryParse(portRaw.split(':')[2].split(' ')[0], radix: 16)
          .toString();
    }
  }
  if (ports.isEmpty) {
    ports = "None";
  }
  return ports;
}

// Global vars
String cmds = '';

/// Rename Dialog
/// @param context: context
/// @param item: distro name
/// @param statusMsg: Function(String, {bool loading})
settingsDialog(
    context, item, Function(String, {bool loading}) statusMsg) async {
  var title = 'settings-text'.i18n();
  final pathController = TextEditingController();
  pathController.text = prefs.getString('StartPath_$item') ?? '';
  final userController = TextEditingController();
  userController.text = prefs.getString('StartUser_$item') ?? '';
  plausible.event(page: title.split(' ')[0].toLowerCase());
  bool isSyncing = false;
  String ip = await WSLApi().execCmdAsRoot(item, 'hostname --all-ip-addresses');
  String portsTcp =
      extractPorts(await WSLApi().execCmdAsRoot(item, 'cat /proc/net/tcp'));
  String portsUdp =
      extractPorts(await WSLApi().execCmdAsRoot(item, 'cat /proc/net/udp'));
  String portsTcp6 =
      extractPorts(await WSLApi().execCmdAsRoot(item, 'cat /proc/net/tcp6'));
  String portsUdp6 =
      extractPorts(await WSLApi().execCmdAsRoot(item, 'cat /proc/net/udp6'));
  showDialog(
    context: context,
    builder: (childcontext) {
      return ContentDialog(
        constraints: const BoxConstraints(maxHeight: 500.0, maxWidth: 500.0),
        title: Text(title),
        content: StatefulBuilder(builder: (BuildContext context, setState) {
          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: settingsColumn(
                  pathController,
                  userController,
                  context,
                  item,
                  statusMsg,
                  ip,
                  portsTcp,
                  portsTcp6,
                  portsUdp,
                  portsUdp6,
                  isSyncing,
                  setState),
            ),
          );
        }),
        actions: [
          Button(
              child: Text('cancel-text'.i18n()),
              onPressed: () {
                Navigator.pop(context);
              }),
          Button(
              child: Text('save-text'.i18n()),
              onPressed: () {
                prefs.setString('StartPath_$item', pathController.text);
                prefs.setString('StartUser_$item', userController.text);
                Navigator.pop(context);
              }),
        ],
      );
    },
  );
}

Column settingsColumn(
    TextEditingController pathController,
    TextEditingController userController,
    context,
    item,
    Function(String, {bool loading}) statusMsg,
    String ip,
    String portsTcp,
    String portsTcp6,
    String portsUdp,
    String portsUdp6,
    bool isSyncing,
    Function setState) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 8.0),
        child: Text('save-text'.i18n()),
      ),
      Tooltip(
        message: 'startdirectorypath-text'.i18n(),
        child: TextBox(
          controller: pathController,
          placeholder: '/home/user/project',
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 8.0, top: 8.0),
        child: Text('startuser-text'.i18n()),
      ),
      Tooltip(
        message: 'wsldefaultuser-text'.i18n(),
        child: TextBox(
          controller: userController,
          placeholder: 'root',
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 8.0, top: 8.0),
        child: Text('emptyfieldsfordefault-text'.i18n()),
      ),
      const SizedBox(
        height: 8.0,
      ),
      SizedBox(
        width: MediaQuery.of(context).size.width,
        child: Builder(builder: (childcontext) {
          List<MenuFlyoutItem> actions = [];
          List<String>? quickSettingsTitles =
              prefs.getStringList("quickSettingsTitles");
          List<String>? quickSettingsContents =
              prefs.getStringList("quickSettingsContents");
          if (quickSettingsContents != null && quickSettingsTitles != null) {
            for (int i = 0; i < quickSettingsTitles.length; i++) {
              actions.add(MenuFlyoutItem(
                leading: const MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Icon(FluentIcons.play),
                  ),
                ),
                onPressed: () async {
                  plausible.event(page: 'use_action');
                  setState(() {
                    cmds = '';
                  });
                  await Future.delayed(const Duration(milliseconds: 500));
                  // Add new
                  setState(() {
                    cmds = quickSettingsContents[i];
                  });
                },
                text: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Text(quickSettingsTitles[i])),
              ));
            }
          }
          return actions.isNotEmpty
              ? MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: DropDownButton(
                    buttonStyle: ButtonStyle(
                        padding: ButtonState.all(const EdgeInsets.only(
                            left: 15.0, right: 15.0, top: 10.0, bottom: 10.0))),
                    leading: const Icon(FluentIcons.code),
                    title: Text('runquickaction-text'.i18n()),
                    items: actions,
                  ),
                )
              : const SizedBox();
        }),
      ),
      const SizedBox(
        height: 12.0,
      ),
      cmds.isNotEmpty
          ? Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Console(
                item: item,
                cmds: cmds,
                afterInit: () {
                  cmds = '';
                },
              ),
            )
          : Container(),
      Container(
        width: MediaQuery.of(context).size.width,
        color: themeData.activeColor.withOpacity(0.1),
        child: Padding(
          padding: const EdgeInsets.all(4.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText('eth0 IPv4: ${ip.replaceAll('\n', ' ')}'),
              SelectableText('TCP ${'ports-text'.i18n()}: $portsTcp'),
              SelectableText('TCP6 ${'ports-text'.i18n()}: $portsTcp6'),
              SelectableText('UDP ${'ports-text'.i18n()}: $portsUdp'),
              SelectableText('UDP6 ${'ports-text'.i18n()}: $portsUdp6'),
            ],
          ),
        ),
      ),
      const SizedBox(
        height: 12.0,
      ),
      Sync().hasPath(item)
          ? MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Tooltip(
                message: 'upload-text'.i18n(),
                child: Button(
                  style: ButtonStyle(
                      padding: ButtonState.all(const EdgeInsets.only(
                          left: 15.0, right: 15.0, top: 10.0, bottom: 10.0))),
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('startstopserving-text'.i18n()),
                        const Icon(FluentIcons.upload),
                      ]),
                  onPressed: () {
                    plausible.event(name: "network_uploaded");
                    Sync sync = Sync.instance(item, statusMsg);
                    if (!isSyncing) {
                      isSyncing = true;
                      sync.startServer();
                      statusMsg('startedserving-text'.i18n([item]));
                    } else {
                      isSyncing = false;
                      sync.stopServer();
                      statusMsg('stoppedserving-text'.i18n([item]));
                    }
                  },
                ),
              ),
            )
          : Container(),
      const SizedBox(height: 8.0),
      Sync().hasPath(item)
          ? MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Tooltip(
                message: 'download-text'.i18n(),
                child: Button(
                  style: ButtonStyle(
                      padding: ButtonState.all(const EdgeInsets.only(
                          left: 15.0, right: 15.0, top: 10.0, bottom: 10.0))),
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('downloadoverride-text'.i18n()),
                        const Icon(FluentIcons.download),
                      ]),
                  onPressed: () {
                    plausible.event(name: "network_downloaded");
                    syncDialog(context, item, statusMsg);
                  },
                ),
              ),
            )
          : Container(),
    ],
  );
}
