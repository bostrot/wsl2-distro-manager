import 'analytics.dart';
import 'api.dart';
import 'dialog.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

late SharedPreferences prefs;

class DistroList extends StatefulWidget {
  const DistroList({Key? key, required this.api, required this.statusMsg})
      : super(key: key);

  final WSLApi api;
  final Function(String, {bool loading}) statusMsg;

  @override
  _DistroListState createState() => _DistroListState();
}

class _DistroListState extends State<DistroList> {
  Map<String, bool> hover = {};
  void update(var item, bool enter) {
    setState(() {
      hover[item] = enter;
    });
  }

  // Initialize shared preferences
  void initPrefs() async {
    prefs = await SharedPreferences.getInstance();
  }

  @override
  void initState() {
    initPrefs();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return distroList(widget.api, widget.statusMsg, update, hover);
  }
}

FutureBuilder<Instances> distroList(
    WSLApi api,
    Function(String, {bool loading}) statusMsg,
    Function(dynamic, bool) update,
    Map<String, bool> hover) {
  isRunning(String distroName, List<String> runningList) {
    if (runningList.contains(distroName)) {
      return true;
    }
    return false;
  }

  // List as FutureBuilder with WSLApi
  return FutureBuilder<Instances>(
    future: api.list(),
    builder: (context, snapshot) {
      if (snapshot.hasData) {
        List<Widget> newList = [];
        List<String> list = snapshot.data?.all ?? [];
        List<String> running = snapshot.data?.running ?? [];
        // Check if there are distros
        if (list.isEmpty) {
          return const Expanded(
            child: Center(
              child: Text('No distros found.'),
            ),
          );
        }
        // Check if WSL is installed
        if (list[0] == 'wslNotInstalled') {
          return const InstallDialog();
        }
        for (String item in list) {
          newList.add(Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: MouseRegion(
              onEnter: (event) {
                update(item, true);
              },
              onExit: (event) {
                update(item, false);
              },
              child: ListTile(
                tileColor: (hover[item] != null && hover[item]!)
                    ? const Color.fromRGBO(0, 0, 0, 0.2)
                    : Colors.transparent,
                /* tileColor: Colors.black,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(10.0))), */
                title: isRunning(item, running)
                    ? (Text(distroLabel(item) + ' (running)'))
                    : Text(distroLabel(item)), // running here
                leading: Row(children: [
                  Tooltip(
                    message: 'Start',
                    child: IconButton(
                      icon: const Icon(FluentIcons.play),
                      onPressed: () {
                        plausible.event(name: "wsl_started");
                        String? startPath =
                            prefs.getString('StartPath_' + item) ?? '';
                        String? startName =
                            prefs.getString('StartUser_' + item) ?? '';
                        api.start(item,
                            startPath: startPath, startUser: startName);
                        Future.delayed(const Duration(milliseconds: 500),
                            statusMsg('$item started.'));
                      },
                    ),
                  ),
                  isRunning(item, running)
                      ? Tooltip(
                          message: 'Stop',
                          child: IconButton(
                            icon: const Icon(FluentIcons.stop),
                            onPressed: () {
                              plausible.event(name: "wsl_stopped");
                              api.stop(item);
                              statusMsg('$item stopped.');
                            },
                          ),
                        )
                      : const Text(''),
                ]),
                trailing: Row(
                  children: [
                    Tooltip(
                      message: 'Open with File Explorer',
                      child: IconButton(
                        icon: const Icon(FluentIcons.open_folder_horizontal),
                        onPressed: () async {
                          plausible.event(name: "wsl_explorer");
                          String? path =
                              prefs.getString('StartPath_' + item) ?? '';
                          api.startExplorer(item, path: path);
                        },
                      ),
                    ),
                    Tooltip(
                      message: 'Open with Visual Studio Code',
                      child: IconButton(
                        icon: const Icon(FluentIcons.visual_studio_for_windows),
                        onPressed: () async {
                          plausible.event(name: "wsl_vscode");
                          // Get path
                          String? path =
                              prefs.getString('StartPath_' + item) ?? '';
                          api.startVSCode(item, path: path);
                        },
                      ),
                    ),
                    Tooltip(
                      message: 'Copy',
                      child: IconButton(
                        icon: const Icon(FluentIcons.copy),
                        onPressed: () async {
                          copyDialog(context, item, api, statusMsg);
                        },
                      ),
                    ),
                    Tooltip(
                      message: 'Rename',
                      child: IconButton(
                        icon: const Icon(FluentIcons.rename),
                        onPressed: () {
                          renameDialog(context, item, api, statusMsg);
                        },
                      ),
                    ),
                    Tooltip(
                      message: 'Delete',
                      child: IconButton(
                          icon: const Icon(FluentIcons.delete),
                          onPressed: () {
                            deleteDialog(context, item, api, statusMsg);
                          }),
                    ),
                    Tooltip(
                      message: 'Settings',
                      child: IconButton(
                          icon: const Icon(FluentIcons.settings),
                          onPressed: () {
                            settingsDialog(context, item, api, statusMsg);
                          }),
                    ),
                  ],
                ),
              ),
            ),
          ));
        }
        return Expanded(
          child: ListView.custom(
            childrenDelegate: SliverChildListDelegate(newList),
          ),
        );
      } else if (snapshot.hasError) {
        return Text('${snapshot.error}');
      }

      // By default, show a loading spinner.
      return const Center(child: ProgressRing());
    },
  );
}

/// Delete Dialog
/// @param context: context
/// @param item: distro name
/// @param api: WSLApi
/// @param statusMsg: status message
deleteDialog(context, item, api, Function(String, {bool loading}) statusMsg) {
  dialog(
      context: context,
      item: item,
      api: api,
      statusMsg: statusMsg,
      title: 'Delete \'${distroLabel(item)}\' permanently?',
      body: 'If you delete this Distro you won\'t be able to recover it.'
          ' Do you want to delete it?',
      submitText: 'Delete',
      submitInput: false,
      submitStyle: ButtonStyle(
        backgroundColor: ButtonState.all(Colors.red),
        foregroundColor: ButtonState.all(Colors.white),
      ),
      onSubmit: (inputText) async {
        api.remove(item);
        statusMsg('DONE: Deleted $item.');
      });
}

/// Rename Dialog
/// @param context: context
/// @param item: distro name
/// @param api: WSLApi
/// @param statusMsg: Function(String, {bool loading})
settingsDialog(context, item, api, Function(String, {bool loading}) statusMsg) {
  var title = 'Settings';
  final pathController = TextEditingController();
  pathController.text = prefs.getString('StartPath_' + item) ?? '';
  final userController = TextEditingController();
  userController.text = prefs.getString('StartUser_' + item) ?? '';
  plausible.event(page: title.split(' ')[0].toLowerCase());
  showDialog(
    context: context,
    builder: (context) {
      return ContentDialog(
        title: Text(title),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8.0),
              child: Text('Start directory path'),
            ),
            Tooltip(
              message: '(Optional) WSL directory to start in.',
              child: TextBox(
                controller: pathController,
                placeholder: '/home/user/project',
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 8.0, top: 8.0),
              child: Text('Start user'),
            ),
            Tooltip(
              message: '(Optional) WSL default user to use.',
              child: TextBox(
                controller: userController,
                placeholder: 'root',
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 8.0, top: 8.0),
              child: Text(
                  '(empty the fields for default or if your WSL version does not support it)'),
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
              child: const Text('Save'),
              onPressed: () {
                prefs.setString('StartPath_' + item, pathController.text);
                prefs.setString('StartUser_' + item, userController.text);
                Navigator.pop(context);
              }),
        ],
      );
    },
  );
}

/// Get distro label from item
/// @param item: distro name
/// @returns String
String distroLabel(String item) {
  String? distroName = prefs.getString('DistroName_' + item);
  if (distroName == null || distroName == '') {
    distroName = item;
  }
  return distroName;
}

/// Rename Dialog
/// @param context: context
/// @param item: distro name
/// @param api: WSLApi
/// @param statusMsg: Function(String, {bool loading})
renameDialog(context, item, api, Function(String, {bool loading}) statusMsg) {
  dialog(
      context: context,
      item: item,
      api: api,
      statusMsg: statusMsg,
      title: 'Rename \'${distroLabel(item)}\'',
      body: 'Warning: Renaming will only change the label of the distro '
          'in this application. '
          '\n\nLeave this empty for the default name.',
      submitText: 'Rename',
      submitStyle: const ButtonStyle(),
      onSubmit: (inputText) async {
        statusMsg('Renaming $item to $inputText...', loading: true);
        prefs.setString('DistroName_' + item, inputText);
        statusMsg('DONE: Renamed ${distroLabel(item)} to $inputText.');
      });
}

/// Copy Dialog
/// @param context: context
/// @param item: distro name
/// @param api: WSLApi
/// @param statusMsg: Function(String, {bool loading})
copyDialog(context, item, api, Function(String, {bool loading}) statusMsg) {
  dialog(
      context: context,
      item: item,
      api: api,
      statusMsg: statusMsg,
      title: 'Copy \'$item\'',
      body: 'Copy the WSL instance \'${distroLabel(item)}\' to a new instance'
          'with this name.',
      submitText: 'Copy',
      submitStyle: const ButtonStyle(),
      onSubmit: (inputText) async {
        statusMsg('Copying $item. This might take a while...', loading: true);
        await api.copy(item, inputText);
        // Copy settings
        String? startPath = prefs.getString('StartPath_' + item) ?? '';
        String? startName = prefs.getString('StartUser_' + item) ?? '';
        prefs.setString('StartPath_' + item, startPath);
        prefs.setString('StartUser_' + item, startName);
        statusMsg('DONE: Copied ${distroLabel(item)} to $inputText.');
      });
}

/// Install Dialog
class InstallDialog extends StatelessWidget {
  const InstallDialog({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text('WSL is not installed.'),
            const Padding(
              padding: EdgeInsets.only(bottom: 8.0),
              child: Text(
                  'You can install it with following command in the Terminal:'),
            ),
            Container(
              color: const Color.fromRGBO(0, 0, 0, 0.2),
              child: Padding(
                  padding: const EdgeInsets.only(left: 4.0, right: 4.0),
                  child: TextButton(
                      onPressed: () async {
                        plausible.event(name: "wsl_install");
                        WSLApi().installWSL();
                      },
                      child: const Text("wsl --install"))),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 8.0),
              child:
                  Text('Hint: you can click the above command to install it'),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 8.0),
              child: Text('(Keep '
                  'in mind that you need to restart your system to complete the'
                  ' install.)'),
            ),
          ],
        ),
      ),
    );
  }
}
