import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:wsl2distromanager/components/navbar.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/components/analytics.dart';

class SettingsPage extends StatefulWidget {
  SettingsPage({Key? key, required this.themeData}) : super(key: key);

  final ThemeData themeData;

  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final locationController = TextEditingController();
  //plausible.event(page: 'create');

  @override
  Widget build(BuildContext context) {
    return NavigationView(
      content: Column(
        children: [
          navbar(widget.themeData, back: true, context: context),
          const Text('Default Distro location'),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: SizedBox(
              width: 300.0,
              child: Tooltip(
                message: 'Path where to save copied distros by default',
                child: TextBox(
                  controller: locationController,
                  placeholder:
                      prefs.getString("SaveLocation") ?? 'C:\\WSL2-Distros',
                  suffix: IconButton(
                    icon: const Icon(FluentIcons.open_folder_horizontal,
                        size: 15.0),
                    onPressed: () async {
                      String? path =
                          await FilePicker.platform.getDirectoryPath();
                      if (path != null) {
                        locationController.text = path;
                      } else {
                        // User canceled the picker
                      }
                    },
                  ),
                ),
              ),
            ),
          ),
          Button(
              child: const Text('Save'),
              style: ButtonStyle(
                  padding: ButtonState.all(const EdgeInsets.only(
                      left: 15.0, right: 15.0, top: 10.0, bottom: 10.0))),
              onPressed: () {
                if (locationController.text.isNotEmpty) {
                  prefs.setString("SaveLocation", locationController.text);
                }
                Navigator.pop(context);
              }),
        ],
      ),
    );
  }
}
