import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:localization/localization.dart';
import 'package:wsl2distromanager/components/analytics.dart';
import 'package:wsl2distromanager/api/wsl.dart';
import 'package:wsl2distromanager/components/constants.dart';
import 'package:wsl2distromanager/components/navbar.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:system_info2/system_info2.dart';
import 'package:wsl2distromanager/nav/router.dart';
import 'package:wsl2distromanager/theme.dart';

enum SettingsType { bool, text, size }

class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  SettingsPageState createState() => SettingsPageState();
}

class SettingsPageState extends State<SettingsPage> {
  Map<String, TextEditingController> _settings =
      <String, TextEditingController>{};

  final TextEditingController _syncIpTextController = TextEditingController();
  final TextEditingController _syncPasswordController = TextEditingController();
  final TextEditingController _repoTextController = TextEditingController();
  final TextEditingController _dockerrepoController = TextEditingController();
  final TextEditingController _editorController = TextEditingController();
  final TextEditingController _terminalController = TextEditingController();
  final TextEditingController _vscodeController = TextEditingController();
  final TextEditingController _dockerMirrorController = TextEditingController();
  bool showDocker = false;
  BuildContext? currentContext;

  @override
  void initState() {
    super.initState();
    readData();
  }

  @override
  void dispose() {
    // Save settings
    if (currentContext != null) {
      saveSettings(currentContext!, dispose: true);
    }
    super.dispose();
  }

  void readData() async {
    final Map<String, String> settings = await WSLApi().readConfig();
    settings.forEach((key, value) {
      _settings[key] = TextEditingController(text: value);
    });
    String? syncIP = prefs.getString('SyncIP');
    if (syncIP != null && syncIP != '') {
      _syncIpTextController.text = syncIP;
    }
    String? syncPassword = prefs.getString('SyncPassword');
    if (syncPassword != null && syncPassword != '') {
      _syncPasswordController.text = syncPassword;
    }
    String? repoLink = prefs.getString('RepoLink');
    if (repoLink != null && repoLink != '') {
      _repoTextController.text = repoLink;
    }
    if (prefs.containsKey('DockerRepoLink')) {
      String? dockerRepoLink = prefs.getString('DockerRepoLink');
      if (dockerRepoLink != null && dockerRepoLink != '') {
        _dockerrepoController.text = dockerRepoLink;
      }
    }
    String? editor = prefs.getString('Editor');
    if (editor != null && editor != '') {
      _editorController.text = editor;
    }
    String? terminal = prefs.getString('Terminal');
    if (terminal != null && terminal != '') {
      _terminalController.text = terminal;
    }
    String? vscodeCmd = prefs.getString('VSCodeCmd');
    if (vscodeCmd != null && vscodeCmd != '') {
      _vscodeController.text = vscodeCmd;
    }
    String? dockerMirror = prefs.getString('DockerMirror');
    if (dockerMirror != null && dockerMirror != '') {
      _dockerMirrorController.text = dockerMirror;
    }
    showDocker = prefs.getBool('showDocker') ?? false;
    if (!mounted) return;
    setState(() {
      _settings = _settings;
    });
  }

  @override
  Widget build(BuildContext context) {
    currentContext = context;
    return Column(
      mainAxisSize: MainAxisSize.max,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(top: 20.0, left: 20.0, right: 20.0),
            child: SizedBox(
              child: settingsList(context),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(
              left: 20.0, right: 20.0, bottom: 8.0, top: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Tooltip(
                message: 'editwslconfig-text'.i18n(),
                child: Button(
                    style: ButtonStyle(
                        padding: ButtonState.all(const EdgeInsets.only(
                            left: 15.0, right: 15.0, top: 10.0, bottom: 10.0))),
                    onPressed: () {
                      WSLApi().editConfig();
                    },
                    child: Text('editwslconfig-text'.i18n())),
              ),
              const SizedBox(
                width: 10.0,
              ),
              Row(
                children: [
                  Tooltip(
                    message: 'stopwsl-text'.i18n(),
                    child: Button(
                        style: ButtonStyle(
                            padding: ButtonState.all(const EdgeInsets.only(
                                left: 15.0,
                                right: 15.0,
                                top: 10.0,
                                bottom: 10.0))),
                        onPressed: () {
                          WSLApi().restart();
                          hasPushed = false;

                          Navigator.popAndPushNamed(context, '/');
                        },
                        child: Text('stopwsl-text'.i18n())),
                  ),
                  const SizedBox(
                    width: 10.0,
                  ),
                  Tooltip(
                    message: 'save-text'.i18n(),
                    child: Button(
                        style: ButtonStyle(
                            padding: ButtonState.all(const EdgeInsets.only(
                                left: 15.0,
                                right: 20.0,
                                top: 10.0,
                                bottom: 10.0))),
                        onPressed: () {
                          saveSettings(context);
                        },
                        child: Text('save-text'.i18n())),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  void saveSettings(BuildContext context, {bool dispose = false}) {
    plausible.event(name: "global_settings_saved");
    // Sync target ip setting _syncIpTextController
    if (_syncIpTextController.text.isNotEmpty) {
      prefs.setString("SyncIP", _syncIpTextController.text);
    }

    // Sync password
    if (_syncPasswordController.text.isNotEmpty) {
      prefs.setString("SyncPassword", _syncPasswordController.text);
    } else {
      prefs.remove("SyncPassword");
    }

    // Save repo link
    if (_repoTextController.text.isNotEmpty) {
      prefs.setString("RepoLink", _repoTextController.text);
    } else {
      prefs.setString("RepoLink", defaultRepoLink);
    }

    // Save docker repo link
    if (_dockerrepoController.text.isNotEmpty) {
      prefs.setString("DockerRepoLink", _dockerrepoController.text);
    } else {
      prefs.setString("DockerRepoLink", "https://registry-1.docker.io");
    }

    // Save editor
    if (_editorController.text.isNotEmpty) {
      prefs.setString("Editor", _editorController.text);
    } else {
      prefs.remove("Editor");
    }

    // Save terminal
    if (_terminalController.text.isNotEmpty) {
      prefs.setString("Terminal", _terminalController.text);
    } else {
      prefs.remove("Terminal");
    }

    // Save vscode command
    if (_vscodeController.text.isNotEmpty) {
      prefs.setString("VSCodeCmd", _vscodeController.text);
    } else {
      prefs.remove("VSCodeCmd");
    }

    // Save docker mirror
    if (_dockerMirrorController.text.isNotEmpty) {
      prefs.setString("DockerMirror", _dockerMirrorController.text);
    } else {
      prefs.remove("DockerMirror");
    }

    // Distro location setting
    if (_settings['Default Distro Location']!.text.isNotEmpty) {
      prefs.setString("DistroPath", _settings['Default Distro Location']!.text);
    }
    // Data location setting
    if (_settings['General Data Location']!.text.isNotEmpty) {
      prefs.setString("DataPath", _settings['General Data Location']!.text);
    }
    _settings.forEach((key, value) {
      if (key != 'Default Distro Location' &&
          key != 'General Data Location' &&
          value.text.isNotEmpty) {
        WSLApi().setConfig('wsl2', key, value.text);
      }
    });
    hasPushed = false;

    if (!dispose) {
      router.pushNamed('home');
    }
  }

  Widget settingsList(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        settingsWidget(context,
            title: 'defaultdistrolocation-text'.i18n(),
            name: 'Default Distro Location',
            tooltip: 'distropath-text'.i18n(),
            suffix: IconButton(
              icon: const Icon(FluentIcons.open_folder_horizontal, size: 15.0),
              onPressed: () async {
                String? path = await FilePicker.platform.getDirectoryPath(
                  initialDirectory:
                      prefs.getString("DistroPath") ?? defaultPath,
                );
                if (path != null &&
                    _settings['Default Distro Location'] != null) {
                  _settings['Default Distro Location']!.text = path;
                } else {
                  // User canceled the picker
                }
              },
            ),
            placeholder: prefs.getString("DistroPath") ?? defaultPath),
        settingsWidget(context,
            title: 'defaultdatalocation-text'.i18n(),
            name: 'General Data Location',
            tooltip: 'datapath-text'.i18n(),
            suffix: IconButton(
              icon: const Icon(FluentIcons.open_folder_horizontal, size: 15.0),
              onPressed: () async {
                String? path = await FilePicker.platform.getDirectoryPath(
                  initialDirectory: prefs.getString("DataPath") ??
                      prefs.getString("DistroPath") ??
                      defaultPath,
                );
                if (path != null &&
                    _settings['General Data Location'] != null) {
                  _settings['General Data Location']!.text = path;
                } else {
                  // User canceled the picker
                }
              },
            ),
            placeholder: prefs.getString("DataPath") ??
                prefs.getString("DistroPath") ??
                defaultPath),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: InfoLabel(
            label: 'defaulteditor-text'.i18n(),
            labelStyle: const TextStyle(fontWeight: FontWeight.w500),
            child: Tooltip(
              message: 'defaulteditor-text'.i18n(),
              child: TextBox(
                controller: _editorController,
                placeholder: 'notepad.exe',
                suffix: IconButton(
                  icon: const Icon(FluentIcons.open_folder_horizontal,
                      size: 15.0),
                  onPressed: () async {
                    FilePickerResult? result =
                        await FilePicker.platform.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: ['exe'],
                    );
                    if (result != null) {
                      _editorController.text = result.files.single.path!;
                    }
                  },
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: InfoLabel(
            label: 'defaultterminal-text'.i18n(),
            labelStyle: const TextStyle(fontWeight: FontWeight.w500),
            child: Tooltip(
              message: 'defaultterminal-text'.i18n(),
              child: TextBox(
                controller: _terminalController,
                placeholder: 'wt.exe',
                suffix: IconButton(
                  icon: const Icon(FluentIcons.open_folder_horizontal,
                      size: 15.0),
                  onPressed: () async {
                    FilePickerResult? result =
                        await FilePicker.platform.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: ['exe'],
                    );
                    if (result != null) {
                      _terminalController.text = result.files.single.path!;
                    }
                  },
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: InfoLabel(
            label: 'defaultvscode-text'.i18n(),
            labelStyle: const TextStyle(fontWeight: FontWeight.w500),
            child: Tooltip(
              message: 'defaultvscode-text'.i18n(),
              child: TextBox(
                controller: _vscodeController,
                placeholder: 'code',
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: InfoLabel(
            label: 'dockermirror-text'.i18n(),
            labelStyle: const TextStyle(fontWeight: FontWeight.w500),
            child: Tooltip(
              message: 'dockermirrorhint-text'.i18n(),
              child: TextBox(
                controller: _dockerMirrorController,
                placeholder: 'https://mirror.gcr.io',
              ),
            ),
          ),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: InfoLabel(
              label: 'showdockershort-text'.i18n(),
              labelStyle: const TextStyle(fontWeight: FontWeight.w500),
              child: Row(
                children: [
                  Tooltip(
                      message: 'showdockershort-text'.i18n(),
                      child: ToggleSwitch(
                        checked: showDocker,
                        onChanged: (value) {
                          setState(() {
                            showDocker = value;
                            prefs.setBool('showDocker', value);
                          });
                        },
                      )),
                  const SizedBox(
                    width: 10.0,
                  ),
                  Text('showdockerlong-text'.i18n()),
                ],
              ),
            ),
          ),
        ]),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: InfoLabel(
              label: 'language-text'.i18n(),
              labelStyle: const TextStyle(fontWeight: FontWeight.w500),
              child: Tooltip(
                  message: 'language-text'.i18n(),
                  // Menu
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'languagechange-text'.i18n(),
                      ),
                      const SizedBox(
                        height: 20.0,
                      ),
                      Builder(
                        builder: (context) {
                          var lang =
                              Localizations.localeOf(context).languageCode;
                          var selectedLanguage =
                              prefs.getString('language') ?? lang;

                          // Language menu
                          return ComboBox<String>(
                              value: selectedLanguage,
                              items: supportedLocalesList
                                  .map((e) => ComboBoxItem(
                                      value: e.languageCode,
                                      child: Text(e.toString())))
                                  .toList(),
                              onChanged: (language) {
                                String curLanguage = language ?? lang;
                                prefs.setString('language', curLanguage);
                                setState(() {
                                  selectedLanguage = curLanguage;
                                });
                              });
                        },
                      ),
                    ],
                  )),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: InfoLabel(
              label: 'dockerrepo-text'.i18n(),
              labelStyle: const TextStyle(fontWeight: FontWeight.w500),
              child: Tooltip(
                message: 'dockerrepo-text'.i18n(),
                child: TextBox(
                  controller: _dockerrepoController,
                  placeholder: 'https://registry-1.docker.io',
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: InfoLabel(
              label: 'syncipaddress-text'.i18n(),
              labelStyle: const TextStyle(fontWeight: FontWeight.w500),
              child: Tooltip(
                message: 'syncipaddress-text'.i18n(),
                child: TextBox(
                  controller: _syncIpTextController,
                  placeholder: '192.168.1.20',
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: InfoLabel(
              label: 'syncpassword-text'.i18n(),
              labelStyle: const TextStyle(fontWeight: FontWeight.w500),
              child: Tooltip(
                message: 'syncpasswordhint-text'.i18n(),
                child: TextBox(
                  controller: _syncPasswordController,
                  placeholder: 'SecretPassword123',
                  obscureText: true,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: InfoLabel(
              label: 'repofordistro-text'.i18n(),
              labelStyle: const TextStyle(fontWeight: FontWeight.w500),
              child: Tooltip(
                message: 'repofordistro-text'.i18n(),
                child: TextBox(
                  controller: _repoTextController,
                  placeholder: defaultRepoLink,
                ),
              ),
            ),
          ),
        ]),
        const Padding(
          padding: EdgeInsets.only(top: 8.0, bottom: 8.0),
          child: Divider(),
        ),
        Center(
          child: Text("globalconfiguration-text".i18n()),
        ),
        Padding(
          padding: const EdgeInsets.all(10.0),
          child: Text(
            'globalconfigurationinfo-text'.i18n(),
            style: const TextStyle(fontSize: 12.0, fontStyle: FontStyle.italic),
          ),
        ),
        settingsWidget(context,
            title: 'kernel',
            tooltip: 'absolutewindowspath-text'.i18n(),
            placeholder: ''),
        settingsWidget(context,
            title: 'memory',
            tooltip: 'memoryinfo-text'.i18n(),
            type: SettingsType.size,
            sizePostfix: 'GB',
            sizeMin: 1,
            sizeMax:
                (SysInfo.getTotalPhysicalMemory() ~/ 1024 ~/ 1024 ~/ 1024) + 1,
            placeholder: ''),
        settingsWidget(context,
            title: 'processors',
            tooltip: 'processorinfo-text'.i18n(),
            type: SettingsType.size,
            sizeMin: 1,
            sizeMax: SysInfo.cores.length,
            placeholder: ''),
        settingsWidget(context,
            title: 'localhostForwarding',
            tooltip: 'wildcardinfo-text'.i18n(),
            type: SettingsType.bool),
        settingsWidget(context,
            title: 'kernelCommandLine',
            tooltip: 'kernelcmdinfo-text'.i18n(),
            placeholder: ''),
        settingsWidget(context,
            title: 'swap', tooltip: 'swapinfo-text'.i18n(), placeholder: ''),
        settingsWidget(context,
            title: 'swapFile', tooltip: 'vhdinfo-text'.i18n(), placeholder: ''),
        settingsWidget(context,
            title: 'guiApplications',
            tooltip: 'guiinfo-text'.i18n(),
            type: SettingsType.bool),
        settingsWidget(context,
            title: 'debugConsole',
            tooltip: 'consoleinfo-text'.i18n(),
            type: SettingsType.bool),
        settingsWidget(context,
            title: 'nestedVirtualization',
            tooltip: 'nestedvirtinfo-text'.i18n(),
            type: SettingsType.bool),
        settingsWidget(context,
            title: 'vmIdleTimeout',
            tooltip: 'vmidleinfo-text'.i18n(),
            placeholder: ''),
      ],
    );
  }

  Widget settingsWidget(
    BuildContext context, {
    String title = '',
    String name = '',
    String tooltip = '',
    dynamic suffix = 0,
    String placeholder = '',
    SettingsType type = SettingsType.text,
    String sizePostfix = '',
    int sizeMax = 0,
    int sizeMin = 0,
  }) {
    if (name.isEmpty) {
      name = title;
    }
    if (_settings[name] == null) {
      _settings[name] = TextEditingController(text: '');
    }
    // First letter to capital
    title = title.replaceFirst(title[0], title[0].toUpperCase());
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: InfoLabel(
        label: title,
        labelStyle: const TextStyle(fontWeight: FontWeight.w500),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (tooltip.isNotEmpty && tooltip != title)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Text(tooltip,
                    style: TextStyle(color: Colors.grey[100], fontSize: 12)),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 0.0),
              child: Builder(
                builder: (context) {
                  double size = double.tryParse(
                          _settings[name]!.text.replaceAll(sizePostfix, '')) ??
                      sizeMin.toDouble();
                  switch (type) {
                    case SettingsType.text:
                      return TextBox(
                        controller: _settings[name],
                        placeholder: placeholder,
                        suffix: suffix != 0 ? suffix : Container(),
                      );
                    case SettingsType.bool:
                      return ToggleSwitch(
                          checked: _settings[name]!.text == 'true',
                          onChanged: (value) {
                            _settings[name]!.text = value ? 'true' : 'false';
                            setState(() {
                              _settings = _settings;
                            });
                          },
                          content: Text(_settings[name]!.text));
                    case SettingsType.size:
                      if (_settings[name] == null) {
                        _settings[name] = TextEditingController(
                            text: sizeMin.toDouble().toString());
                      }
                      return SizedBox(
                          width: MediaQuery.of(context).size.width,
                          child: Slider(
                              min: sizeMin.toDouble(),
                              max: sizeMax.toDouble(),
                              //divisions: 1,
                              value: size,
                              style: SliderThemeData(
                                labelBackgroundColor: AppTheme().color,
                              ),
                              onChanged: (value) {
                                setState(() {
                                  _settings[name]!.text =
                                      value.toInt().toString() + sizePostfix;
                                });
                              },
                              label: _settings[name]!.text));
                    default:
                      return TextBox(
                        controller: _settings[name],
                        placeholder: placeholder,
                        suffix: suffix != 0 ? suffix : Container(),
                      );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
