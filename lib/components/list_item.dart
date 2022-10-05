import 'package:localization/localization.dart';
import 'package:wsl2distromanager/components/api.dart';
import 'analytics.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/dialogs/dialogs.dart';

class ListItem extends StatefulWidget {
  const ListItem(
      {Key? key,
      required this.item,
      required this.statusMsg,
      required this.running})
      : super(key: key);
  final List<String> running;
  final String item;
  final Function(String, {bool loading}) statusMsg;
  @override
  State<ListItem> createState() => _ListItemState();
}

class _ListItemState extends State<ListItem> {
  Map<String, bool> hover = {};
  bool isSyncing = false;
  bool showBar = false;
  bool hovered = false;

  void syncing(var item) {
    setState(() {
      isSyncing = item;
    });
  }

  isRunning(String distroName, List<String> runningList) {
    if (runningList.contains(distroName)) {
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8.0, left: 12.0, right: 12.0),
      child: Expander(
          initiallyExpanded: false,
          leading: Row(children: [
            Tooltip(
              message: 'start-text'.i18n(),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: IconButton(
                  icon: const Icon(FluentIcons.play),
                  onPressed: () {
                    startInstance();
                  },
                ),
              ),
            ),
            isRunning(widget.item, widget.running)
                ? Tooltip(
                    message: 'stop-text'.i18n(),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: IconButton(
                        icon: const Icon(FluentIcons.stop),
                        onPressed: () {
                          stopInstance();
                        },
                      ),
                    ),
                  )
                : const Text(''),
          ]),
          header: isRunning(widget.item, widget.running)
              ? (Text('${distroLabel(widget.item)} (${'running-text'.i18n()})'))
              : Text(distroLabel(widget.item)),
          content: Bar(
            widget: widget,
          )),
    );
  }

  void stopInstance() {
    plausible.event(name: "wsl_stopped");
    WSLApi().stop(widget.item);
    widget.statusMsg('${widget.item} ${'stopped-text'.i18n()}.',
        loading: false);
  }

  void startInstance() {
    plausible.event(name: "wsl_started");
    String? startPath = prefs.getString('StartPath_${widget.item}') ?? '';
    String? startName = prefs.getString('StartUser_${widget.item}') ?? '';
    String startCmd = '';
    if (prefs.getBool('TurnkeyFirstStart_${widget.item}') ?? false) {
      startCmd = 'turnkey-init';
      prefs.setBool('TurnkeyFirstStart_${widget.item}', false);
    }
    // Normal start
    WSLApi().start(widget.item,
        startPath: startPath, startUser: startName, startCmd: startCmd);

    Future.delayed(const Duration(milliseconds: 500),
        widget.statusMsg('${widget.item} ${'started-text'.i18n()}.'));
  }
}

class Bar extends StatelessWidget {
  const Bar({Key? key, required this.widget}) : super(key: key);

  final ListItem widget;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
          borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(5.0),
              bottomRight: Radius.circular(5.0))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Tooltip(
            message: 'openwithexplorer-text'.i18n(),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: IconButton(
                icon:
                    const Icon(FluentIcons.open_folder_horizontal, size: 16.0),
                onPressed: () {
                  plausible.event(name: "wsl_explorer");
                  String? path =
                      prefs.getString('StartPath_${widget.item}') ?? '';
                  WSLApi().startExplorer(widget.item, path: path);
                },
              ),
            ),
          ),
          Tooltip(
            message: 'openwithwt-text'.i18n(),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: IconButton(
                icon: const Icon(FluentIcons.power_shell, size: 16.0),
                onPressed: () {
                  plausible.event(name: "wsl_wt");
                  String? path =
                      prefs.getString('StartPath_${widget.item}') ?? '';
                  WSLApi().startWindowsTerminal(widget.item, path: path);
                },
              ),
            ),
          ),
          Tooltip(
            message: 'openwithvscode-text'.i18n(),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: IconButton(
                icon: const Icon(FluentIcons.visual_studio_for_windows,
                    size: 16.0),
                onPressed: () {
                  plausible.event(name: "wsl_vscode");
                  // Get path
                  String? path =
                      prefs.getString('StartPath_${widget.item}') ?? '';
                  WSLApi().startVSCode(widget.item, path: path);
                },
              ),
            ),
          ),
          Tooltip(
            message: 'copy-text'.i18n(),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: IconButton(
                icon: const Icon(FluentIcons.copy, size: 16.0),
                onPressed: () {
                  copyDialog(context, widget.item, widget.statusMsg);
                },
              ),
            ),
          ),
          Tooltip(
            message: 'rename-text'.i18n(),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: IconButton(
                icon: const Icon(FluentIcons.rename, size: 16.0),
                onPressed: () {
                  renameDialog(context, widget.item, widget.statusMsg);
                },
              ),
            ),
          ),
          Tooltip(
            message: 'delete-text'.i18n(),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: IconButton(
                  icon: const Icon(FluentIcons.delete, size: 16.0),
                  onPressed: () {
                    deleteDialog(context, widget.item, widget.statusMsg);
                  }),
            ),
          ),
          Tooltip(
            message: 'settings-text'.i18n(),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: IconButton(
                  icon: const Icon(FluentIcons.settings, size: 16.0),
                  onPressed: () {
                    settingsDialog(context, widget.item, widget.statusMsg);
                  }),
            ),
          ),
        ],
      ),
    );
  }
}
