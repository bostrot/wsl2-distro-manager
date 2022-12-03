import 'dart:async';

import 'package:localization/localization.dart';
import 'package:wsl2distromanager/api/wsl.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:wsl2distromanager/dialogs/dialogs.dart';
import 'list_item.dart';
import 'helpers.dart';

class DistroList extends StatefulWidget {
  const DistroList({Key? key, required this.api}) : super(key: key);

  final WSLApi api;

  @override
  DistroListState createState() => DistroListState();
}

class DistroListState extends State<DistroList> {
  Map<String, bool> hover = {};
  bool isSyncing = false;
  bool showDocker = false;

  void syncing(var item) {
    if (mounted) {
      setState(() {
        isSyncing = item;
      });
    }
  }

  @override
  void initState() {
    initPrefs();
    // Get shared prefs for showing docker containers
    showDocker = prefs.getBool('showDocker') ?? false;
    reloadEvery5Seconds();
    super.initState();
  }

  void reloadEvery5Seconds() async {
    for (;;) {
      await Future.delayed(const Duration(seconds: 5));
      // Check if state disposed
      if (mounted) {
        setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return distroList(widget.api, widget.statusMsg, hover, showDocker);
  }
}

FutureBuilder<Instances> distroList(
    WSLApi api,
    Function(String, {bool loading}) statusMsg,
    Map<String, bool> hover,
    bool showDocker) {
  // List as FutureBuilder with WSLApi
  return FutureBuilder<Instances>(
    future: api.list(showDocker),
    builder: (context, snapshot) {
      // Update every 20 seconds
      if (snapshot.hasData) {
        List<Widget> newList = [];
        List<String> list = snapshot.data?.all ?? [];
        List<String> running = snapshot.data?.running ?? [];
        // Check if there are distros
        if (list.isEmpty) {
          return Expanded(
            child: Center(
              child: Text('noinstancesfound-text'.i18n()),
            ),
          );
        }
        // Check if WSL is installed
        if (list[0] == 'wslNotInstalled') {
          return const InstallDialog();
        }
        for (String item in list) {
          newList.add(
              ListItem(item: item, statusMsg: statusMsg, running: running));
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
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20.0),
        child: Center(child: ProgressRing()),
      );
    },
  );
}
