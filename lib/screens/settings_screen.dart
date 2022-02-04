import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:wsl2distromanager/components/api.dart';
import 'package:wsl2distromanager/components/navbar.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/components/analytics.dart';

class SettingsPage extends StatefulWidget {
  SettingsPage({Key? key, required this.themeData}) : super(key: key);

  final ThemeData themeData;

  @override
  _SettingsPageState createState() => _SettingsPageState();
}

Map<String, TextEditingController> _settings =
    <String, TextEditingController>{};

class _SettingsPageState extends State<SettingsPage> {
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
    setState(() {
      _settings = _settings;
    });
  }

  //plausible.event(page: 'create');
  @override
  Widget build(BuildContext context) {
    return NavigationView(
      content: Column(
        mainAxisSize: MainAxisSize.max,
        children: [
          navbar(widget.themeData, back: true, context: context),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(left: 20.0, right: 20.0),
              child: SizedBox(
                width: 400.0,
                child: settingsList(context),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Button(
                    child: const Text('Edit .wslconfig directly'),
                    style: ButtonStyle(
                        padding: ButtonState.all(const EdgeInsets.only(
                            left: 15.0, right: 15.0, top: 10.0, bottom: 10.0))),
                    onPressed: () {
                      WSLApi().editConfig();
                    }),
                const SizedBox(
                  width: 180.0,
                ),
                Button(
                    child: const Text('Save'),
                    style: ButtonStyle(
                        padding: ButtonState.all(const EdgeInsets.only(
                            left: 15.0, right: 15.0, top: 10.0, bottom: 10.0))),
                    onPressed: () {
                      if (_settings['Default Distro Location'] != null) {
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
                      Navigator.pop(context);
                    }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget settingsList(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        settingsWidget(context,
            title: 'Default Distro Location',
            tooltip: 'Path where to save copied distros by default',
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
            placeholder: prefs.getString("SaveLocation") ?? 'C:\\WSL2-Distros'),
        const Padding(
          padding: EdgeInsets.only(top: 8.0, bottom: 8.0),
          child: Divider(),
        ),
        const Center(
          child: Text("Global Configuration"),
        ),
        const Padding(
          padding: EdgeInsets.all(8.0),
          child: Text(
            'Note: Global configuration options with .wslconfig is only available for'
            ' distributions running as WSL 2 in Windows Build 19041 and later. '
            'Keep in mind you may need to run wsl --shutdown to shut down the '
            'WSL 2 VM and then restart your WSL instance for these changes to '
            'take affect.',
            style: TextStyle(fontSize: 12.0, fontStyle: FontStyle.italic),
          ),
        ),
        settingsWidget(context,
            title: 'kernel',
            tooltip: 'An absolute Windows path to a custom Linux kernel.',
            placeholder: ''),
        settingsWidget(context,
            title: 'memory',
            tooltip: 'How much memory to assign to the WSL 2 VM.',
            placeholder: ''),
        settingsWidget(context,
            title: 'processors',
            tooltip: 'How many processors to assign to the WSL 2 VM.',
            placeholder: ''),
        settingsWidget(context,
            title: 'localhostForwarding',
            tooltip: 'Boolean specifying if ports bound to wildcard or '
                'localhost in the WSL 2 VM should be connectable from the '
                'host via localhost:port.',
            checkbox: true),
        settingsWidget(context,
            title: 'kernelCommandLine',
            tooltip: 'Additional kernel command line arguments.',
            placeholder: ''),
        settingsWidget(context,
            title: 'swap',
            tooltip: 'How much swap space to add to the WSL 2 VM, 0 for '
                'no swap file. Swap storage is disk-based RAM used when '
                'memory demand exceeds limit on hardware device.',
            placeholder: ''),
        settingsWidget(context,
            title: 'swapFile',
            tooltip: 'An absolute Windows path to the swap virtual hard disk.',
            placeholder: ''),
        settingsWidget(context,
            title: 'pageReporting',
            tooltip: 'Default true setting enables Windows to reclaim '
                'unused memory allocated to WSL 2 virtual machine.',
            checkbox: true),
        settingsWidget(context,
            title: 'guiApplications',
            tooltip: 'Boolean to turn on or off support for GUI applications '
                '(WSLg) in WSL. Only available for Windows 11.',
            checkbox: true),
        settingsWidget(context,
            title: 'debugConsole',
            tooltip: 'Boolean to turn on an output console Window that shows '
                'the contents of dmesg upon start of a WSL 2 distro instance. '
                'Only available for Windows 11.',
            checkbox: true),
        settingsWidget(context,
            title: 'nestedVirtualization',
            tooltip: 'Boolean to turn on or off nested virtualization, '
                'enabling other nested VMs to run inside WSL 2. Only available '
                'for Windows 11.',
            checkbox: true),
        settingsWidget(context,
            title: 'vmIdleTimeout',
            tooltip: 'The number of milliseconds that a VM is idle, before '
                'it is shut down. Only available for Windows 11.',
            placeholder: ''),
      ],
    );
  }

  Widget settingsWidget(
    BuildContext context, {
    title = '',
    tooltip = '',
    suffix = 0,
    placeholder = '',
    checkbox = false,
  }) {
    if (_settings[title] == null) {
      _settings[title] = TextEditingController(text: '');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title),
        Padding(
          padding: const EdgeInsets.only(bottom: 8.0, top: 4.0),
          child: Tooltip(
            message: tooltip,
            child: checkbox
                ? Checkbox(
                    checked: _settings[title]!.text == 'true',
                    onChanged: (value) {
                      if (value != null) {
                        _settings[title]!.text = value ? 'true' : 'false';
                        setState(() {
                          _settings = _settings;
                        });
                      }
                    })
                : TextBox(
                    controller: _settings[title],
                    placeholder: placeholder,
                    suffix: suffix != 0 ? suffix : Container(),
                  ),
          ),
        ),
      ],
    );
  }
}
