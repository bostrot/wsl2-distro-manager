import 'package:wsl2distromanager/components/analytics.dart';
import 'package:fluent_ui/fluent_ui.dart';
// import 'package:wsl2distromanager/components/api.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/components/sync.dart';
import 'package:wsl2distromanager/dialogs/sync_dialog.dart';

/// Rename Dialog
/// @param context: context
/// @param item: distro name
/// @param statusMsg: Function(String, {bool loading})
settingsDialog(context, item, Function(String, {bool loading}) statusMsg) {
  var title = 'Settings';
  final pathController = TextEditingController();
  pathController.text = prefs.getString('StartPath_' + item) ?? '';
  final userController = TextEditingController();
  userController.text = prefs.getString('StartUser_' + item) ?? '';
  plausible.event(page: title.split(' ')[0].toLowerCase());
  bool isSyncing = false;
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
            Sync().hasPath(item)
                ? Tooltip(
                    message: 'Upload',
                    child: Button(
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: const [
                            Text('Start/Stop serving on network'),
                            Icon(FluentIcons.upload),
                          ]),
                      onPressed: () {
                        //plausible.event(name: "wsl_started");
                        Sync sync = Sync.instance(item, statusMsg);
                        if (!isSyncing) {
                          isSyncing = true;
                          sync.startServer();
                          statusMsg('Serving $item on network.');
                        } else {
                          isSyncing = false;
                          sync.stopServer();
                          statusMsg('Stopped serving $item on network.');
                        }
                      },
                    ),
                  )
                : Container(),
            const SizedBox(height: 8.0),
            Sync().hasPath(item)
                ? Tooltip(
                    message: 'Download',
                    child: Button(
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: const [
                            Text('Download/Override from network'),
                            Icon(FluentIcons.download),
                          ]),
                      onPressed: () {
                        //plausible.event(name: "wsl_started");
                        syncDialog(context, item, statusMsg);
                      },
                    ),
                  )
                : Container(),
            const SizedBox(
              height: 8.0,
            ),
            /* Button(
                child: const Text('Edit startup file'),
                style: ButtonStyle(
                    padding: ButtonState.all(const EdgeInsets.only(
                        left: 15.0, right: 15.0, top: 10.0, bottom: 10.0))),
                onPressed: () {
                  WSLApi().openBashrc(item);
                }), */
          ],
        ),
        actions: [
          Button(
              child: const Text('Cancel'),
              onPressed: () {
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
