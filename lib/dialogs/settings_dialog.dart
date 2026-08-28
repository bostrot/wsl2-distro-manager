import 'dart:async';

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

/// How the `wsl.conf` editor reaches WSL.
///
/// The dialog is built from top-level functions with no injection point, so
/// this is the seam the widget tests replace to keep `wsl.exe` out of them.
WSLApi Function() wslApiBuilder = () => WSLApi();

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
        padding: const EdgeInsets.only(bottom: 2.0, top: 8.0),
        child: Text('startuser-text'.i18n()),
      ),
      // The narrow one. It only becomes `--user` on terminals this app
      // launches, which is why it used to be mistaken for the wsl.conf key
      // rendered right below it (audit coverage-sweep S-1).
      Padding(
        padding: const EdgeInsets.only(bottom: 4.0),
        child: Text('startuserinfo-text'.i18n(),
            style: FluentTheme.of(context).typography.caption),
      ),
      TextBox(
        controller: userController,
        placeholder: 'root',
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 8.0, top: 8.0),
        child: Text('emptyfieldsfordefault-text'.i18n()),
      ),
      // The real one: `[user] default` in /etc/wsl.conf, which the app wrote
      // at creation and then never let anyone see again (audit CC-6).
      Text('user-text'.i18n()),
      settingText(item, setState, userDefaultSetting),
      const SizedBox(
        height: 8.0,
      ),
      wslSettings(context, item, setState),
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

/// One documented `/etc/wsl.conf` key, with everything the dialog needs to
/// render it.
///
/// The dialog used to derive its labels from the Dart identifier —
/// `"MountFsTab"`, `"AppendWindowsPath"` — with no description and no
/// `.i18n()` call anywhere, which made it the largest i18n gap the WSL
/// documentation audit found (doc/audit/wsl-docs/wslconf-keys.md CC-4).
class WslConfSetting {
  final String section;
  final String key;

  /// i18n key of the label, and of the sentence under it.
  final String labelKey;
  final String infoKey;

  final bool isToggle;

  /// What WSL does when the key is absent, where the documentation states it.
  ///
  /// Null means the default is not a fixed value — `[boot] systemd` is
  /// whatever the distro image ships — so an unset key renders off and says
  /// so rather than claiming a default it does not have.
  final bool? defaultOn;

  final String? placeholder;

  const WslConfSetting.toggle(
    this.section,
    this.key,
    this.labelKey,
    this.infoKey, {
    this.defaultOn,
  })  : isToggle = true,
        placeholder = null;

  const WslConfSetting.text(
    this.section,
    this.key,
    this.labelKey,
    this.infoKey, {
    this.placeholder,
  })  : isToggle = false,
        defaultOn = null;

  /// Suffix of this key's `SharedPreferences` entry, under `<distro>-`.
  ///
  /// The spelling here is the documented one, and [WslConfFile] normalises the
  /// file's spelling to match on read, so a hand-written `mountfstab = true`
  /// reaches the widget that renders it (audit V-7).
  String get prefKey => '$section-$key';
}

/// Every documented `wsl.conf` key, in the order the dialog renders them.
///
/// `[gpu] enabled`, `[time] useWindowsTimezone` and `[boot] protectBinfmt`
/// were missing entirely; `[user] default` was written once at distro creation
/// and never shown again (audit CC-6).
const List<WslConfSetting> wslConfSettings = <WslConfSetting>[
  WslConfSetting.toggle(
      'boot', 'systemd', 'bootsystemd-text', 'bootsystemdinfo-text'),
  WslConfSetting.text(
      'boot', 'command', 'bootcommand-text', 'bootcommandinfo-text',
      placeholder: 'service docker start'),
  WslConfSetting.toggle(
      'boot', 'protectBinfmt', 'protectbinfmt-text', 'protectbinfmtinfo-text',
      defaultOn: true),
  WslConfSetting.toggle('automount', 'enabled', 'automountenabled-text',
      'automountenabledinfo-text',
      defaultOn: true),
  WslConfSetting.toggle('automount', 'mountFsTab', 'automountmountfstab-text',
      'automountmountfstabinfo-text',
      defaultOn: true),
  WslConfSetting.text(
      'automount', 'root', 'automountroot-text', 'automountrootinfo-text',
      placeholder: '/mnt/'),
  WslConfSetting.text('automount', 'options', 'automountoptions-text',
      'automountoptionsinfo-text',
      placeholder: 'metadata,uid=1000,gid=1000,umask=22'),
  WslConfSetting.toggle('network', 'generateHosts', 'networkgeneratehosts-text',
      'networkgeneratehostsinfo-text',
      defaultOn: true),
  WslConfSetting.toggle('network', 'generateResolvConf',
      'networkgenerateresolvconf-text', 'networkgenerateresolvconfinfo-text',
      defaultOn: true),
  WslConfSetting.text('network', 'hostname', 'networkhostname-text',
      'networkhostnameinfo-text'),
  WslConfSetting.toggle(
      'interop', 'enabled', 'interopenabled-text', 'interopenabledinfo-text',
      defaultOn: true),
  WslConfSetting.toggle('interop', 'appendWindowsPath',
      'interopappendwindowspath-text', 'interopappendwindowspathinfo-text',
      defaultOn: true),
  WslConfSetting.toggle(
      'gpu', 'enabled', 'gpuenabled-text', 'gpuenabledinfo-text',
      defaultOn: true),
  WslConfSetting.toggle('time', 'useWindowsTimezone', 'usewindowstimezone-text',
      'usewindowstimezoneinfo-text',
      defaultOn: true),
  // Rendered next to the "Start user" box instead of in an Expander — see
  // [userDefaultSetting].
  WslConfSetting.text(
      'user', 'default', 'wsldefaultuser-text', 'defaultuserinfo-text',
      placeholder: 'root'),
];

/// `[user] default`, the one documented way to change the default user of an
/// imported distro (`basic-commands.md:152`).
///
/// It is deliberately not inside the `wsl.conf` Expanders: the dialog already
/// shows a **Start user** box that only sets `--user` on terminals this app
/// launches, and a user hunting for this setting finds that one first and
/// stops looking (audit coverage-sweep S-1). The two sit together, each
/// saying what it does.
final WslConfSetting userDefaultSetting =
    wslConfSettings.firstWhere((s) => s.section == 'user');

/// i18n key of each section's Expander header.
const Map<String, String> wslConfSectionLabels = <String, String>{
  'boot': 'boot-text',
  'automount': 'automount-text',
  'network': 'network-text',
  'interop': 'interop-text',
  'gpu': 'gpu-text',
  'time': 'time-text',
};

/// The `wsl.conf` editor: one Expander per documented section.
Widget wslSettings(BuildContext context, String item, Function setState) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('wslsettings-text'.i18n()),
      const SizedBox(height: 4.0),
      // No wsl.conf key takes effect while the distro is still running — the
      // documented "8 second rule" (wsl-config.md:20-26). A per-distro
      // terminate is enough; the global shutdown the .wslconfig screen needs
      // is not (audit runtime R-12).
      Text('wslconfrestart-text'.i18n(),
          style: FluentTheme.of(context).typography.caption),
      const SizedBox(height: 8.0),
      for (final section in wslConfSectionLabels.entries) ...[
        Expander(
          header: Text(section.value.i18n()),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final setting
                  in wslConfSettings.where((s) => s.section == section.key))
                wslConfField(item, setState, setting),
            ],
          ),
        ),
        const SizedBox(height: 8.0),
      ],
      MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Button(
          style: ButtonStyle(
              padding: ButtonState.all(const EdgeInsets.only(
                  left: 15.0, right: 15.0, top: 10.0, bottom: 10.0))),
          child:
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('terminatedistro-text'.i18n()),
            const Icon(FluentIcons.power_button),
          ]),
          onPressed: () async {
            await wslApiBuilder().stop(item);
            Notify.message('terminatedistro-text'.i18n());
          },
        ),
      ),
    ],
  );
}

/// The widget [setting] is rendered by.
Widget wslConfField(String item, Function setState, WslConfSetting setting) {
  return setting.isToggle
      ? settingSwitch(item, setState, setting)
      : settingText(item, setState, setting);
}

/// True when [setting] has a line in this distro's `wsl.conf`.
///
/// `loadDistroSettings` clears every known key and then writes back only the
/// ones physically present, so the preference's existence *is* the key's.
bool _isSet(String item, WslConfSetting setting) =>
    prefs.containsKey('$item-${setting.prefKey}');

/// Report a failed write. The old writer returned `true` unconditionally and
/// ran with `showOutput: false`, so a `sed` that never fired still showed as
/// applied (audit CC-2).
void _reportWrite(bool ok, WslConfSetting setting) {
  if (!ok) {
    Notify.message('wslconfwritefailed-text'.i18n([setting.labelKey.i18n()]));
  }
}

/// Label, description and — when the key is actually in the file — the
/// control that takes it back out again.
Widget _settingHeader(BuildContext context, String item, Function setState,
    WslConfSetting setting,
    {Widget? leading}) {
  final theme = FluentTheme.of(context);
  final isSet = _isSet(item, setting);
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (leading != null) ...[leading, const SizedBox(width: 8.0)],
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(setting.labelKey.i18n()),
            const SizedBox(height: 2.0),
            Text(setting.infoKey.i18n(), style: theme.typography.caption),
            if (!isSet)
              Text('settingunset-text'.i18n(),
                  style: theme.typography.caption
                      ?.copyWith(color: theme.accentColor)),
          ],
        ),
      ),
      if (isSet)
        Tooltip(
          message: 'settingdefault-text'.i18n(),
          child: IconButton(
            icon: const Icon(FluentIcons.undo),
            onPressed: () async {
              await prefs.remove('$item-${setting.prefKey}');
              setState(() {});
              _reportWrite(
                  await wslApiBuilder()
                      .removeSetting(item, setting.section, setting.key),
                  setting);
            },
          ),
        ),
    ],
  );
}

/// A boolean `wsl.conf` key.
///
/// Unset renders as the *documented* default, not as off. Six keys are
/// documented `true` and the old switch showed every one of them off on a
/// distro whose `wsl.conf` is absent or near-empty, which is most of them
/// (audit CC-3). Turning a key back to unset removes its line, so there is a
/// real third state rather than a relabelled `false`.
Widget settingSwitch(String item, Function setState, WslConfSetting setting) {
  final stored = prefs.get('$item-${setting.prefKey}');
  final checked = stored is bool ? stored : (setting.defaultOn ?? false);
  return Padding(
    padding: const EdgeInsets.all(8.0),
    child: Builder(
      builder: (context) => _settingHeader(
        context,
        item,
        setState,
        setting,
        leading: Padding(
          padding: const EdgeInsets.only(top: 2.0),
          child: ToggleSwitch(
            checked: checked,
            onChanged: (value) async {
              await prefs.setBool('$item-${setting.prefKey}', value);
              setState(() {});
              _reportWrite(
                  await wslApiBuilder().setSetting(
                      item, setting.section, setting.key, value.toString()),
                  setting);
            },
          ),
        ),
      ),
    ),
  );
}

/// A free-text `wsl.conf` key.
Widget settingText(String item, Function setState, WslConfSetting setting) {
  return _WslConfTextField(
    key: ValueKey('$item-${setting.prefKey}'),
    item: item,
    setting: setting,
    setState: setState,
  );
}

/// A text key that writes once the value settles instead of once per
/// keystroke.
///
/// `onChanged` used to run a full in-distro script execution per character
/// typed (audit CC-5). The debounce plus the commit on blur means a
/// twelve-character hostname is one write, and the write still happens without
/// the user hunting for a Save button — which is the behaviour the dialog has
/// always had.
class _WslConfTextField extends StatefulWidget {
  final String item;
  final WslConfSetting setting;
  final Function setState;

  const _WslConfTextField({
    super.key,
    required this.item,
    required this.setting,
    required this.setState,
  });

  @override
  State<_WslConfTextField> createState() => _WslConfTextFieldState();
}

class _WslConfTextFieldState extends State<_WslConfTextField> {
  static const Duration _debounce = Duration(milliseconds: 700);

  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late String _committed;
  Timer? _timer;

  String get _prefKey => '${widget.item}-${widget.setting.prefKey}';

  @override
  void initState() {
    super.initState();
    _committed = prefs.getString(_prefKey) ?? '';
    _controller = TextEditingController(text: _committed);
    _focusNode = FocusNode();
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) _commit();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _commit() async {
    _timer?.cancel();
    final value = _controller.text;
    if (value == _committed) return;
    _committed = value;

    // An emptied box means "unset", which has to delete the line: writing
    // `hostname =` back would pin the distro to an empty value instead of
    // letting WSL fall back to the Windows computer name.
    final bool ok;
    if (value.isEmpty) {
      await prefs.remove(_prefKey);
      ok = await wslApiBuilder().removeSetting(
          widget.item, widget.setting.section, widget.setting.key);
    } else {
      await prefs.setString(_prefKey, value);
      ok = await wslApiBuilder().setSetting(
          widget.item, widget.setting.section, widget.setting.key, value);
    }
    if (mounted) widget.setState(() {});
    _reportWrite(ok, widget.setting);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _settingHeader(context, widget.item, widget.setState, widget.setting),
          const SizedBox(height: 4.0),
          TextBox(
            controller: _controller,
            focusNode: _focusNode,
            placeholder: widget.setting.placeholder,
            onChanged: (_) {
              _timer?.cancel();
              _timer = Timer(_debounce, _commit);
            },
            onSubmitted: (_) => _commit(),
          ),
        ],
      ),
    );
  }
}

Future<void> loadDistroSettings(String item) async {
  // Clear known wsl.conf settings to avoid stale data. Derived from the
  // rendered list so a key added to `wslConfSettings` cannot be forgotten
  // here and leak its value from the previously opened distro.
  final List<String> knownKeys =
      wslConfSettings.map((setting) => setting.prefKey).toList();

  for (var key in knownKeys) {
    await prefs.remove('$item-$key');
  }

  var config = await wslApiBuilder().getWSLConf(item);
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
          // Keeps the scrollbar off the input fields it would otherwise
          // overlap.
          child: Padding(
            padding: const EdgeInsets.only(right: 14.0),
            child: settingsColumn(
                widget.pathController,
                widget.startCmdController,
                widget.userController,
                context,
                widget.item,
                isSyncing,
                setState),
          ),
        );
      },
    );
  }
}
