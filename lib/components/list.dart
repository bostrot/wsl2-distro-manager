import 'dart:async';

import 'package:localization/localization.dart';
import 'package:wsl2distromanager/api/wsl.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:wsl2distromanager/dialogs/dialogs.dart';
import 'list_item.dart';
import 'helpers.dart';

/// The widget of distros in the main page. This is being refreshed every 5
/// seconds using the reloadEvery5Seconds() function.
class DistroList extends StatefulWidget {
  const DistroList({super.key, required this.api});

  final WSLApi api;

  @override
  DistroListState createState() => DistroListState();
}

class DistroListState extends State<DistroList> {
  Map<String, bool> hover = {};
  bool isSyncing = false;
  bool showDocker = false;
  int reloadTick = 0;

  void syncing(var item) {
    if (mounted) {
      setState(() {
        isSyncing = item;
      });
    }
  }

  void init() async {
    await initPrefs();
    // Get shared prefs for showing docker containers
    showDocker = prefs.getBool('showDocker') ?? false;
    if (mounted) {
      setState(() {});
    }
    reloadEvery5Seconds();
  }

  @override
  void initState() {
    init();
    super.initState();
  }

  void reloadEvery5Seconds() async {
    for (;;) {
      await Future.delayed(const Duration(seconds: 5));
      // Check if state disposed
      if (mounted) {
        setState(() {
          reloadTick++;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final remoteEnabled = widget.api.useRemoteWsl;
    final remoteTarget = widget.api.remoteTargetLabel;

    // List as FutureBuilder with WSLApi
    return FutureBuilder<Instances>(
      key: ValueKey('distro-list-$reloadTick-$showDocker'),
      future: widget.api.list(showDocker),
      initialData: GlobalVariable.initialSnapshot,
      builder: (context, snapshot) {
        // Update every 20 seconds
        if (snapshot.hasData) {
          GlobalVariable.initialSnapshot = snapshot.data;
          List<Widget> newList = [];
          List<String> list = snapshot.data?.all ?? [];
          List<String> running = snapshot.data?.running ?? [];
          // Check if there are distros
          if (list.isEmpty) {
            return Expanded(
              child: Stack(
                children: [
                  const SizedBox.expand(),
                  Center(
                    child: Text('noinstancesfound-text'.i18n()),
                  ),
                  Positioned(
                    right: 20,
                    bottom: 20,
                    child: FilledButton(
                      onPressed: () {
                        createDialog();
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(FluentIcons.add),
                          const SizedBox(width: 8),
                          Text('addinstance-text'.i18n()),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }
          // Check if WSL is installed
          if (list[0] == 'wslNotInstalled') {
            return const InstallDialog();
          }
          for (String item in list) {
            newList.add(ListItem(
              item: item,
              running: running,
              trailing: getInstanceSize(item),
            ));
          }
          return Expanded(
            child: ListView.custom(
              childrenDelegate: SliverChildListDelegate(newList),
            ),
          );
        } else if (snapshot.hasError) {
          final errorText = snapshot.error.toString();
          return Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    remoteEnabled
                        ? 'Remote WSL connection failed (${remoteTarget.isEmpty ? 'unknown target' : remoteTarget}).'
                        : 'Failed to load WSL distros.',
                  ),
                  const SizedBox(height: 8),
                  Text(errorText, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  Button(
                    onPressed: () {
                      if (mounted) {
                        setState(() {
                          reloadTick++;
                        });
                      }
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }

        // By default, show a loading spinner.
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 20.0),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ProgressRing(),
                if (remoteEnabled) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Connecting to remote WSL host ${remoteTarget.isEmpty ? '(not configured)' : remoteTarget}...',
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
