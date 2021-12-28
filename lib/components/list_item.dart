import 'analytics.dart';
import 'package:wsl2distromanager/components/api.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/dialogs/dialogs.dart';

Widget listItem(item, update, hover, isRunning, running, statusMsg, context) {
  WSLApi api = WSLApi();
  return Padding(
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
                String? startPath = prefs.getString('StartPath_' + item) ?? '';
                String? startName = prefs.getString('StartUser_' + item) ?? '';
                api.start(item, startPath: startPath, startUser: startName);
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
                onPressed: () {
                  plausible.event(name: "wsl_explorer");
                  String? path = prefs.getString('StartPath_' + item) ?? '';
                  api.startExplorer(item, path: path);
                },
              ),
            ),
            Tooltip(
              message: 'Open with Visual Studio Code',
              child: IconButton(
                icon: const Icon(FluentIcons.visual_studio_for_windows),
                onPressed: () {
                  plausible.event(name: "wsl_vscode");
                  // Get path
                  String? path = prefs.getString('StartPath_' + item) ?? '';
                  api.startVSCode(item, path: path);
                },
              ),
            ),
            Tooltip(
              message: 'Copy',
              child: IconButton(
                icon: const Icon(FluentIcons.copy),
                onPressed: () {
                  copyDialog(context, item, statusMsg);
                },
              ),
            ),
            Tooltip(
              message: 'Rename',
              child: IconButton(
                icon: const Icon(FluentIcons.rename),
                onPressed: () {
                  renameDialog(context, item, statusMsg);
                },
              ),
            ),
            Tooltip(
              message: 'Delete',
              child: IconButton(
                  icon: const Icon(FluentIcons.delete),
                  onPressed: () {
                    deleteDialog(context, item, statusMsg);
                  }),
            ),
            Tooltip(
              message: 'Settings',
              child: IconButton(
                  icon: const Icon(FluentIcons.settings),
                  onPressed: () {
                    settingsDialog(context, item, statusMsg);
                  }),
            ),
          ],
        ),
      ),
    ),
  );
}
