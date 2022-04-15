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
        constraints: const BoxConstraints(maxHeight: 450.0, maxWidth: 400.0),
        title: const Text('Create a new distro'),
        content: SingleChildScrollView(
          child: CreateWidget(
              nameController: nameController,
              api: api,
              autoSuggestBox: autoSuggestBox,
              locationController: locationController,
              userController: userController,
              statusMsg: statusMsg),
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
              String label = nameController.text;
              // Replace all special characters with _
              String name = label.replaceAll(RegExp('[^A-Za-z0-9]'), '_');
              if (name != '') {
                statusMsg('Creating instance. This might take a while...',
                    loading: true);
                String location = locationController.text;
                if (location == '') {
                  location = prefs.getString("SaveLocation") ?? defaultPath;
                  location += '/' + name;
                }
                var result = await api.create(name, autoSuggestBox.text,
                    location, (String msg) => statusMsg(msg));
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
                    if (Navigator.canPop(context)) {
                      Navigator.pop(context);
                    }
                    // Install fake systemctl
                    if (autoSuggestBox.text.contains('Turnkey')) {
                      statusMsg('Installing fake systemd ...');
                      WSLApi().execCmds(
                          name,
                          [
                            'wget https://raw.githubusercontent.com/bostrot/'
                                'fake-systemd/master/systemctl -O /usr/bin/systemctl',
                            'chmod +x /usr/bin/systemctl',
                            '/usr/bin/systemctl',
                          ],
                          onMsg: (output) => null,
                          onDone: () => statusMsg('DONE: creating instance'));
                    } else {
                      statusMsg('DONE: creating instance');
                    }
                  }
                  // Save distro label
                  prefs.setString('DistroName_' + name, label);
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

class CreateWidget extends StatefulWidget {
  const CreateWidget({
    Key? key,
    required this.nameController,
    required this.api,
    required this.autoSuggestBox,
    required this.locationController,
    required this.userController,
    required this.statusMsg,
  }) : super(key: key);

  final TextEditingController nameController;
  final WSLApi api;
  final TextEditingController autoSuggestBox;
  final TextEditingController locationController;
  final TextEditingController userController;
  final Function(String, {bool loading}) statusMsg;

  @override
  State<CreateWidget> createState() => _CreateWidgetState();
}

class _CreateWidgetState extends State<CreateWidget> {
  bool turnkey = false;
  @override
  Widget build(BuildContext context) {
    return Column(
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
            controller: widget.nameController,
            placeholder: 'Name',
            suffix: IconButton(
              icon: const Icon(FluentIcons.chrome_close, size: 15.0),
              onPressed: () {
                widget.nameController.clear();
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
              'Either use one of the pre-defined Distros or a file path to a '
              'rootfs',
          child: FutureBuilder<List<String>>(
              future: widget.api.getDownloadable(
                  (prefs.getString('RepoLink') ??
                      'http://ftp.halifax.rwth-aachen.de/'
                          'turnkeylinux/images/proxmox/'),
                  (e) => widget.statusMsg(e)),
              builder: (context, snapshot) {
                List<String> list = [];
                if (snapshot.hasData) {
                  list = snapshot.data ?? [];
                } else if (snapshot.hasError) {}
                return AutoSuggestBox(
                  placeholder: 'Distro name or path to rootfs',
                  controller: widget.autoSuggestBox,
                  items: list,
                  onChanged: (String value, TextChangedReason reason) {
                    if (value.contains('Turnkey')) {
                      if (!turnkey) {
                        setState(() {
                          turnkey = true;
                        });
                      }
                    } else {
                      if (turnkey) {
                        setState(() {
                          turnkey = false;
                        });
                      }
                    }
                  },
                  trailingIcon: IconButton(
                    icon: const Icon(FluentIcons.open_folder_horizontal,
                        size: 15.0),
                    onPressed: () async {
                      FilePickerResult? result =
                          await FilePicker.platform.pickFiles(
                        type: FileType.custom,
                        allowedExtensions: ['*'],
                      );

                      if (result != null) {
                        widget.autoSuggestBox.text = result.files.single.path!;
                      } else {
                        // User canceled the picker
                      }
                    },
                  ),
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
            controller: widget.locationController,
            placeholder: 'Save location (optional)',
            suffix: IconButton(
              icon: const Icon(FluentIcons.open_folder_horizontal, size: 15.0),
              onPressed: () async {
                String? path = await FilePicker.platform.getDirectoryPath();
                if (path != null) {
                  widget.locationController.text = path;
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
        turnkey
            ? const Text(
                'Warning: You selected a turnkey container. [Experimental]\n'
                'As most of them use systemd and WSL currently does not '
                'support systemd out of the box it will '
                'be replaced with a fork of fake_systemd. This will start the '
                'applications not on init but on console openings for more info '
                'check the GitHub project\'s README.\n'
                'To access the service you can use "ip a | grep inet" to find '
                'the ip and then navigate to WSL-IP:PORT e.g. in your browser.',
                style: TextStyle(fontStyle: FontStyle.italic))
            : Container(),
        !turnkey
            ? const Text(
                'Create default user (only on Debian/Ubuntu):',
              )
            : Container(),
        !turnkey
            ? Container(
                height: 5.0,
              )
            : Container(),
        !turnkey
            ? Tooltip(
                message: '(Optional) Username',
                child: TextBox(
                  controller: widget.userController,
                  placeholder: '(Optional) User',
                ),
              )
            : Container(),
      ],
    );
  }
}
