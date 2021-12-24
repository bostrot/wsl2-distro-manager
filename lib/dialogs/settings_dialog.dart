import 'package:wsl2distromanager/components/analytics.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:wsl2distromanager/components/helpers.dart';

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
