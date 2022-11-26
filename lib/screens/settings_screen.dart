import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:localization/localization.dart';
import 'package:wsl2distromanager/components/analytics.dart';
import 'package:wsl2distromanager/components/api.dart';
import 'package:wsl2distromanager/components/constants.dart';
import 'package:wsl2distromanager/components/navbar.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:system_info2/system_info2.dart';
import 'package:wsl2distromanager/components/theme.dart';

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
  final TextEditingController _repoTextController = TextEditingController();

  @override
  void initState() {
    super.initState();
    readData();
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
    String? repoLink = prefs.getString('RepoLink');
    if (repoLink != null && repoLink != '') {
      _repoTextController.text = repoLink;
    }
    setState(() {
      _settings = _settings;
    });
  }

  //plausible.event(page: 'create');
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.max,
      children: [
        // TODO: navbar(widget.themeData, back: true, context: context),
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
              Button(
                  style: ButtonStyle(
                      padding: ButtonState.all(const EdgeInsets.only(
                          left: 15.0, right: 15.0, top: 10.0, bottom: 10.0))),
                  onPressed: () {
                    WSLApi().editConfig();
                  },
                  child: Text('editwslconfig-text'.i18n())),
              const SizedBox(
                width: 10.0,
              ),
              Row(
                children: [
                  Button(
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
                  const SizedBox(
                    width: 10.0,
                  ),
                  Button(
                      style: ButtonStyle(
                          padding: ButtonState.all(const EdgeInsets.only(
                              left: 15.0,
                              right: 20.0,
                              top: 10.0,
                              bottom: 10.0))),
                      onPressed: () {
                        plausible.event(name: "global_settings_saved");
                        // Sync target ip setting _syncIpTextController
                        if (_syncIpTextController.text.isNotEmpty) {
                          prefs.setString("SyncIP", _syncIpTextController.text);
                        }

                        // Save repo link
                        if (_repoTextController.text.isNotEmpty) {
                          prefs.setString("RepoLink", _repoTextController.text);
                        } else {
                          prefs.setString("RepoLink", defaultRepoLink);
                        }

                        // Distro location setting
                        if (_settings['Default Distro Location']!
                            .text
                            .isNotEmpty) {
                          prefs.setString("SaveLocation",
                              _settings['Default Distro Location']!.text);
                        }
                        String config = '';
                        _settings.forEach((key, value) {
                          if (key != 'Default Distro Location' &&
                              value.text.isNotEmpty) {
                            config += '$key=${value.text}\n';
                          }
                        });
                        WSLApi().writeConfig(config);
                        hasPushed = false;

                        Navigator.popAndPushNamed(context, '/');
                      },
                      child: Text('save-text'.i18n())),
                ],
              ),
            ],
          ),
        ),
      ],
    );
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
                String? path = await FilePicker.platform.getDirectoryPath();
                if (path != null &&
                    _settings['Default Distro Location'] != null) {
                  _settings['Default Distro Location']!.text = path;
                } else {
                  // User canceled the picker
                }
              },
            ),
            placeholder: prefs.getString("SaveLocation") ?? defaultPath),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Expander(
              header: Text('syncipaddress-text'.i18n(),
                  style: const TextStyle(fontWeight: FontWeight.w500)),
              content: Padding(
                padding: const EdgeInsets.only(bottom: 8.0, top: 4.0),
                child: Tooltip(
                  message: 'syncipaddress-text'.i18n(),
                  child: TextBox(
                    controller: _syncIpTextController,
                    placeholder: '192.168.1.20',
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Expander(
              header: Text('repofordistro-text'.i18n(),
                  style: const TextStyle(fontWeight: FontWeight.w500)),
              content: Padding(
                padding: const EdgeInsets.only(bottom: 8.0, top: 4.0),
                child: Tooltip(
                  message: 'repofordistro-text'.i18n(),
                  child: TextBox(
                    controller: _repoTextController,
                    placeholder: defaultRepoLink,
                  ),
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
            title: 'pageReporting',
            tooltip: 'unusedmemoryinfo-text'.i18n(),
            type: SettingsType.bool),
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
      child: Expander(
        header:
            Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tooltip),
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
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
                                labelBackgroundColor: themeData.disabledColor,
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
