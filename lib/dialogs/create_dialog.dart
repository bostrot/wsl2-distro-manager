import 'package:wsl2distromanager/components/analytics.dart';
import 'package:wsl2distromanager/components/api.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:wsl2distromanager/components/constants.dart';
import 'package:wsl2distromanager/components/helpers.dart';

/// Rename Dialog
/// @param context: context
/// @param api: WSLApi
/// @param statusMsg: Function(String, {bool loading})
createDialog(context, Function(String, {bool loading}) statusMsg) {
  WSLApi api = WSLApi();
  final autoSuggestBox = TextEditingController();
  final locationController = TextEditingController();
  final nameController = TextEditingController();
  final userController = TextEditingController();
  plausible.event(page: 'create');

  showDialog(
    context: context,
    builder: (context) {
      return ContentDialog(
        title: const Text('Create a new distro'),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 10.0,
            ),
            const Text(
              'Name:',
            ),
            Container(
              height: 5.0,
            ),
            Tooltip(
              message: 'The name of your new WSL instance',
              child: TextBox(
                controller: nameController,
                placeholder: 'Name',
                suffix: IconButton(
                  icon: const Icon(FluentIcons.close, size: 15.0),
                  onPressed: () {
                    nameController.clear();
                  },
                ),
              ),
            ),
            Container(
              height: 10.0,
            ),
            const Text(
              'Path to rootfs or distro name:',
            ),
            Container(
              height: 5.0,
            ),
            Tooltip(
              message:
                  'Either use one of the pre-defined Distros or a file path to a rootfs',
              child: FutureBuilder<List<String>>(
                  future: api.getDownloadable(),
                  builder: (context, snapshot) {
                    List<String> list = [];
                    if (snapshot.hasData) {
                      list = snapshot.data ?? [];
                    } else if (snapshot.hasError) {}
                    return AutoSuggestBox<String>(
                      controller: autoSuggestBox,
                      items: list,
                      textBoxBuilder: (context, controller, focusNode, key) {
                        return TextBox(
                          key: key,
                          controller: controller,
                          focusNode: focusNode,
                          suffix: IconButton(
                            icon: const Icon(FluentIcons.open_folder_horizontal,
                                size: 15.0),
                            onPressed: () async {
                              FilePickerResult? result =
                                  await FilePicker.platform.pickFiles(
                                type: FileType.custom,
                                allowedExtensions: ['*'],
                              );

                              if (result != null) {
                                controller.text = result.files.single.path!;
                              } else {
                                // User canceled the picker
                              }
                            },
                          ),
                          placeholder: 'Distro',
                        );
                      },
                    );
                  }),
            ),
            Container(
              height: 10.0,
            ),
            const Text(
              'Save location:',
            ),
            Container(
              height: 5.0,
            ),
            Tooltip(
              message: '(Optional) Path where to save the new instance',
              child: TextBox(
                controller: locationController,
                placeholder: 'Save location (optional)',
                suffix: IconButton(
                  icon: const Icon(FluentIcons.open_folder_horizontal,
                      size: 15.0),
                  onPressed: () async {
                    String? path = await FilePicker.platform.getDirectoryPath();
                    if (path != null) {
                      locationController.text = path;
                    } else {
                      // User canceled the picker
                    }
                  },
                ),
              ),
            ),
            Container(
              height: 10.0,
            ),
            const Text(
              'Create default user (only on Debian/Ubuntu):',
            ),
            Container(
              height: 5.0,
            ),
            Tooltip(
              message: '(Optional) Username',
              child: TextBox(
                controller: userController,
                placeholder: '(Optional) User',
              ),
            ),
          ],
        ),
        actions: [
          Button(
              child: const Text('Cancel'),
              onPressed: () async {
                Navigator.pop(context);
              }),
          Button(
            onPressed: () async {
              plausible.event(name: "wsl_create");
              String name = nameController.text;
              if (name != '') {
                statusMsg('Creating instance. This might take a while...',
                    loading: true);
                String location = locationController.text;
                if (location == '') {
                  location = prefs.getString("SaveLocation") ?? defaultPath;
                  location += '/' + name;
                }
                var result =
                    await api.create(name, autoSuggestBox.text, location);
                if (result.exitCode != 0) {
                  statusMsg(result.stdout);
                } else {
                  String user = userController.text;
                  if (user != '') {
                    List<int> processes = await api.exec(name, [
                      'apt-get update',
                      'apt-get install -y sudo',
                      'useradd -m -s /bin/bash -G sudo $user',
                      'passwd $user',
                      'echo \'$user ALL=(ALL) NOPASSWD:ALL\' >> /etc/sudoers.d/wslsudo',
                      'echo -e \'[user]\ndefault = $user\' > /etc/wsl.conf',
                    ]);
                    bool success = true;
                    for (dynamic process in processes) {
                      if (process != 0) {
                        success = false;
                        break;
                      }
                    }
                    if (success) {
                      prefs.setString('StartPath_' + name, '/home/$user');
                      prefs.setString('StartUser_' + name, user);
                      Navigator.pop(context);
                      statusMsg('DONE: creating instance');
                    } else {
                      Navigator.pop(context);
                      statusMsg(
                          'WARNING: Created instance but failed to create user');
                    }
                  } else {
                    Navigator.pop(context);
                    statusMsg('DONE: creating instance');
                  }
                  // Save distro path
                  prefs.setString('Path_' + name, location);
                }
                // Download distro check
              } else {
                statusMsg('Please type in a name.');
              }
            },
            child: const Text('Create'),
          ),
        ],
      );
    },
  );
}
