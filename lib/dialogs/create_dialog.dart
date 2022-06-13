import 'dart:io';

import 'package:localization/localization.dart';
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
createDialog(
    context, Function mountedFn, Function(String, {bool loading}) statusMsg) {
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
        title: Text('createnewinstance-text'.i18n()),
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
              child: Text('cancel-text'.i18n()),
              onPressed: () async {
                Navigator.pop(context);
              }),
          Button(
            onPressed: () async {
              await createInstance(
                  mountedFn,
                  nameController,
                  statusMsg,
                  locationController,
                  api,
                  autoSuggestBox,
                  userController,
                  context);
            },
            child: Text('create-text'.i18n()),
          ),
        ],
      );
    },
  );
}

Future<void> createInstance(
    Function mountedFn,
    TextEditingController nameController,
    Function(String, {bool loading}) statusMsg,
    TextEditingController locationController,
    WSLApi api,
    TextEditingController autoSuggestBox,
    TextEditingController userController,
    BuildContext context) async {
  plausible.event(name: "wsl_create");
  String label = nameController.text;
  // Replace all special characters with _
  String name = label.replaceAll(RegExp('[^A-Za-z0-9]'), '_');
  if (name != '') {
    statusMsg('creatinginstance-text'.i18n(), loading: true);
    String location = locationController.text;
    if (location == '') {
      location = prefs.getString("SaveLocation") ?? defaultPath;
      location += '/$name';
    }
    Navigator.of(context, rootNavigator: true).pop();
    ProcessResult result = await api.create(
        name, autoSuggestBox.text, location, (String msg) => statusMsg(msg));

    if (result.exitCode != 0) {
      statusMsg(WSLApi().utf8Convert(result.stdout));
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
          prefs.setString('StartPath_$name', '/home/$user');
          prefs.setString('StartUser_$name', user);
          bool mounted = mountedFn();
          if (!mounted) {
            return;
          }

          statusMsg('createdinstance-text'.i18n());
        } else {
          bool mounted = mountedFn();
          if (!mounted) {
            return;
          }
          statusMsg('createdinstancenouser-text'.i18n());
        }
      } else {
        bool mounted = mountedFn();
        if (!mounted) {
          return;
        }

        // Install fake systemctl
        if (autoSuggestBox.text.contains('Turnkey')) {
          // Set first start variable
          prefs.setBool('TurnkeyFirstStart_$name', true);
          statusMsg('installingfakesystemd-text'.i18n(), loading: true);
          WSLApi().execCmds(
              name,
              [
                'wget https://raw.githubusercontent.com/bostrot/'
                    'fake-systemd/master/systemctl -O /usr/bin/systemctl',
                'chmod +x /usr/bin/systemctl',
                '/usr/bin/systemctl',
              ],
              onMsg: (output) => null,
              onDone: () => statusMsg('createdinstance-text'.i18n()));
        } else {
          statusMsg('createdinstance-text'.i18n());
        }
      }
      // Save distro label
      prefs.setString('DistroName_$name', label);
      // Save distro path
      prefs.setString('Path_$name', location);
    }
    // Download distro check
  } else {
    statusMsg('entername-text'.i18n());
  }
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
        Text(
          '${'name-text'.i18n()}:',
        ),
        Container(
          height: 5.0,
        ),
        Tooltip(
          message: 'namehint-text'.i18n(),
          child: TextBox(
            controller: widget.nameController,
            placeholder: 'name-text'.i18n(),
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
        Text(
          '${'pathtorootfs-text'.i18n()}:',
        ),
        Container(
          height: 5.0,
        ),
        Tooltip(
          message: 'pathtorootfshint-text'.i18n(),
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
                  placeholder: 'distroname-text'.i18n(),
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
        Text(
          '${'savelocation-text'.i18n()}:',
        ),
        Container(
          height: 5.0,
        ),
        Tooltip(
          message: 'savelocationhint-text'.i18n(),
          child: TextBox(
            controller: widget.locationController,
            placeholder: 'savelocationplaceholder-text'.i18n(),
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
            ? Text('turnkeywarning-text'.i18n(),
                style: const TextStyle(fontStyle: FontStyle.italic))
            : Container(),
        !turnkey
            ? Text(
                '${'createuser-text'.i18n()}:',
              )
            : Container(),
        !turnkey
            ? Container(
                height: 5.0,
              )
            : Container(),
        !turnkey
            ? Tooltip(
                message: 'optionalusername-text'.i18n(),
                child: TextBox(
                  controller: widget.userController,
                  placeholder: 'optionaluser-text'.i18n(),
                ),
              )
            : Container(),
      ],
    );
  }
}
