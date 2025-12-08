import 'package:localization/localization.dart';
import 'package:wsl2distromanager/components/analytics.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:wsl2distromanager/api/wsl.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/components/notify.dart';
import 'package:wsl2distromanager/components/sync.dart';
import 'package:wsl2distromanager/dialogs/base_dialog.dart';

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
settingsDialog(item) {
  // Get root context by Key
  final context = GlobalVariable.infobox.currentContext!;

  var title = 'settings-text'.i18n();
  final pathController = TextEditingController();
  pathController.text = prefs.getString('StartPath_$item') ?? '';
  final startCmdController = TextEditingController();
  startCmdController.text = prefs.getString('StartCmd_$item') ?? '';
  final userController = TextEditingController();
  userController.text = prefs.getString('StartUser_$item') ?? '';
  plausible.event(page: 'settings_dialog');

  showDialog(
    context: context,
    builder: (childcontext) {
      return ContentDialog(
        constraints: const BoxConstraints(maxHeight: 500.0, maxWidth: 500.0),
        title: Text(title),
        content: SettingsDialogContent(
          item: item,
          pathController: pathController,
          startCmdController: startCmdController,
          userController: userController,
        ),
        actions: [
          Button(
              child: Text('cancel-text'.i18n()),
              onPressed: () {
                Navigator.pop(childcontext);
              }),
          Button(
              child: Text('save-text'.i18n()),
              onPressed: () {
                prefs.setString('StartPath_$item', pathController.text);
                prefs.setString('StartCmd_$item', startCmdController.text);
                prefs.setString('StartUser_$item', userController.text);
                Navigator.pop(childcontext);
              }),
        ],
      );
    },
  );
}

Future<Map<String, String>> getInstanceData(String item) async {
  String ip = await WSLApi().execCmdAsRoot(item, 'hostname --all-ip-addresses');
  String portsTcp =
      extractPorts(await WSLApi().execCmdAsRoot(item, 'cat /proc/net/tcp'));
  String portsUdp =
      extractPorts(await WSLApi().execCmdAsRoot(item, 'cat /proc/net/udp'));
  String portsTcp6 =
      extractPorts(await WSLApi().execCmdAsRoot(item, 'cat /proc/net/tcp6'));
  String portsUdp6 =
      extractPorts(await WSLApi().execCmdAsRoot(item, 'cat /proc/net/udp6'));
  return {
    'ip': ip,
    'portsTcp': portsTcp,
    'portsUdp': portsUdp,
    'portsTcp6': portsTcp6,
    'portsUdp6': portsUdp6,
  };
}

Column settingsColumn(
    TextEditingController pathController,
    TextEditingController startCmdController,
    TextEditingController userController,
    context,
    item,
    bool isSyncing,
    Function setState) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 8.0),
        child: Text('startcommand-text'.i18n()),
      ),
      Tooltip(
        message: 'startcommand-text'.i18n(),
        child: TextBox(
          controller: startCmdController,
          placeholder: 'e.g. /bin/bash',
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 8.0, top: 8.0),
        child: Text('startdirectorypath-text'.i18n()),
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
      wslSettings(item, setState),
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
                    Sync sync = Sync.instance(item);
                    if (!isSyncing) {
                      isSyncing = true;
                      sync.startServer();
                      Notify.message('startedserving-text'.i18n([item]));
                    } else {
                      isSyncing = false;
                      sync.stopServer();
                      Notify.message('stoppedserving-text'.i18n([item]));
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
                    dialog(
                        item: item,
                        title: 'syncfromserver-text'.i18n([distroLabel(item)]),
                        body: 'syncwarning-text'.i18n([item]),
                        submitText: 'yesoverride-text'.i18n(),
                        submitInput: false,
                        submitStyle: ButtonStyle(
                          backgroundColor: ButtonState.all(Colors.red),
                          foregroundColor: ButtonState.all(Colors.white),
                        ),
                        onSubmit: (inputText) {
                          Sync sync = Sync.instance(item);
                          sync.download();
                        });
                  },
                ),
              ),
            )
          : Container(),
      const SizedBox(height: 8.0),
      MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Tooltip(
          message: 'move-text'.i18n(),
          child: Button(
            style: ButtonStyle(
                padding: ButtonState.all(const EdgeInsets.only(
                    left: 15.0, right: 15.0, top: 10.0, bottom: 10.0))),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('move-text'.i18n()),
                  const Icon(FluentIcons.move),
                ]),
            onPressed: () async {
              // Pick directory
              String? selectedDirectory =
                  await FilePicker.platform.getDirectoryPath(
                dialogTitle: 'move-text'.i18n(),
                lockParentWindow: true,
              );

              if (selectedDirectory == null) {
                return;
              }

              dialog(
                  item: item,
                  title: '${'move-text'.i18n()} \'${distroLabel(item)}\'',
                  body: '${'movebody-text'.i18n([
                        distroLabel(item)
                      ])}\n\nTarget: $selectedDirectory',
                  submitText: 'move-text'.i18n(),
                  submitStyle: ButtonStyle(
                    backgroundColor: ButtonState.all(Colors.red),
                    foregroundColor: ButtonState.all(Colors.white),
                  ),
                  submitInput: false,
                  onSubmit: (inputText) async {
                    Notify.message(
                        'moving-text'
                            .i18n([distroLabel(item), selectedDirectory]),
                        loading: true);
                    try {
                      await WSLApi().move(item, selectedDirectory);
                      Notify.message('moved-text'
                          .i18n([distroLabel(item), selectedDirectory]));
                    } catch (e) {
                      Notify.message('move-error-text'.i18n([
                        distroLabel(item),
                        selectedDirectory,
                        e.toString()
                      ]));
                    }
                  });
            },
          ),
        ),
      )
    ],
  );
}

// ToggleSwitch for enabling systemd
Widget wslSettings(item, Function setState) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('wslsettings-text'.i18n()),
      const SizedBox(
        height: 8.0,
      ),
      Expander(
        header: Text('boot-text'.i18n()),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            settingSwitch(item, setState, "boot", "systemd"),
            settingText(item, setState, "boot", "command"),
          ],
        ),
      ),
      const SizedBox(height: 8.0),
      Expander(
        header: Text('automount-text'.i18n()),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            settingSwitch(item, setState, "automount", "enabled"),
            settingSwitch(item, setState, "automount", "mountFsTab"),
            settingText(item, setState, "automount", "root"),
            settingText(item, setState, "automount", "options"),
          ],
        ),
      ),
      const SizedBox(height: 8.0),
      Expander(
        header: Text('network-text'.i18n()),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            settingSwitch(item, setState, "network", "generateHosts"),
            settingSwitch(item, setState, "network", "generateResolvConf"),
            settingText(item, setState, "network", "hostname"),
          ],
        ),
      ),
      const SizedBox(height: 8.0),
      Expander(
        header: Text('interop-text'.i18n()),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            settingSwitch(item, setState, "interop", "enabled"),
            settingSwitch(item, setState, "interop", "appendWindowsPath"),
          ],
        ),
      ),
    ],
  );
}

Widget settingSwitch(item, Function setState, String parent, String setting) {
  final name = setting.uppercaseFirst();
  return Padding(
    padding: const EdgeInsets.all(8.0),
    child: Row(
      children: [
        ToggleSwitch(
          checked: prefs.getBool('$item-$parent-$setting') ?? false,
          onChanged: (value) {
            prefs.setBool('$item-$parent-$setting', value);
            setState(() {});
            // Execute command in WSL
            WSLApi().setSetting(item, parent, setting, value.toString());
          },
        ),
        const SizedBox(
          width: 8.0,
        ),
        Text(name),
      ],
    ),
  );
}

Widget settingText(item, Function setState, String parent, String setting) {
  final name = setting.uppercaseFirst();
  final controller = TextEditingController(
      text: prefs.getString('$item-$parent-$setting') ?? "");
  return Padding(
    padding: const EdgeInsets.all(8.0),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text("$name:"),
        const SizedBox(
          width: 8.0,
        ),
        SizedBox(
          width: 300.0,
          child: TextBox(
            controller: controller,
            onChanged: (value) {
              prefs.setString('$item-$parent-$setting', value);
              // Execute command in WSL
              WSLApi().setSetting(item, parent, setting, value);
            },
          ),
        ),
      ],
    ),
  );
}

Future<void> loadDistroSettings(String item) async {
  var config = await WSLApi().getWSLConf(item);
  config.forEach((section, settings) {
    settings.forEach((key, value) {
      // Handle booleans
      if (value == 'true') {
        prefs.setBool('$item-$section-$key', true);
      } else if (value == 'false') {
        prefs.setBool('$item-$section-$key', false);
      } else {
        prefs.setString('$item-$section-$key', value);
      }
    });
  });
}

class SettingsDialogContent extends StatefulWidget {
  final String item;
  final TextEditingController pathController;
  final TextEditingController startCmdController;
  final TextEditingController userController;

  const SettingsDialogContent({
    Key? key,
    required this.item,
    required this.pathController,
    required this.startCmdController,
    required this.userController,
  }) : super(key: key);

  @override
  State<SettingsDialogContent> createState() => _SettingsDialogContentState();
}

class _SettingsDialogContentState extends State<SettingsDialogContent> {
  late Future<void> _loadFuture;
  bool isSyncing = false;

  @override
  void initState() {
    super.initState();
    _loadFuture = loadDistroSettings(widget.item);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _loadFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 200,
            child: Center(child: ProgressRing()),
          );
        }
        return SingleChildScrollView(
          child: settingsColumn(
              widget.pathController,
              widget.startCmdController,
              widget.userController,
              context,
              widget.item,
              isSyncing,
              setState),
        );
      },
    );
  }
}
