import 'dart:async';

import 'package:localization/localization.dart';
import 'package:wsl2distromanager/api/wsl.dart';
import 'package:wsl2distromanager/api/wsl_errors.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:wsl2distromanager/components/ai_diagnosis.dart';
import 'package:wsl2distromanager/components/error_view.dart';
import 'package:wsl2distromanager/dialogs/dialogs.dart';
import 'package:wsl2distromanager/nav/router.dart';
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
      key: const ValueKey('test-distro-list'),
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
            // Two unrelated states used to share one sentence written from
            // the code's point of view — "No instances found or there is a
            // migration in progress" (audit LN-22). A move leaves its marker
            // in prefs, so the ordinary first-run state can speak to a new
            // user instead.
            final moving = prefs.getString('MoveOp_Distro') != null;
            return Expanded(
              child: Stack(
                children: [
                  const SizedBox.expand(),
                  Center(
                    child: Text((moving
                            ? 'moveinprogress-text'
                            : 'noinstancesfound-text')
                        .i18n()),
                  ),
                  Positioned(
                    right: 20,
                    bottom: 20,
                    child: FilledButton(
                      onPressed: () {
                        router.pushNamed('addinstance');
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
          // Not `snapshot.error.toString()`: that put `Exception: <localized
          // WSL prose>` on the page and offered a Retry that could only fail
          // the same way. The sentence is translated and mapped from the
          // stable error code; the raw text keeps its place underneath, and a
          // remote failure gets the one remedy that actually changes the
          // outcome — going back to the local WSL (audit LN-17, LN-18).
          final failure = WslFailure.from(snapshot.error);
          return Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ErrorBody(
                      failure: failure,
                      leading: remoteEnabled
                          ? 'listfailedremote-text'.i18n([
                              remoteTarget.isEmpty
                                  ? 'remotenotset-text'.i18n()
                                  : remoteTarget
                            ])
                          : 'listfailed-text'.i18n(),
                      hint: remoteEnabled
                          ? 'listfailedremotehint-text'.i18n()
                          : 'listfailedhint-text'.i18n(),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (remoteEnabled)
                          Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: FilledButton(
                              key: const ValueKey('test-list-use-local'),
                              onPressed: () async {
                                await prefs.setBool('UseRemoteWSL', false);
                                if (mounted) {
                                  setState(() {
                                    reloadTick++;
                                  });
                                }
                              },
                              child: Text('uselocalwsl-text'.i18n()),
                            ),
                          ),
                        Button(
                          key: const ValueKey('test-list-retry'),
                          onPressed: () {
                            if (mounted) {
                              setState(() {
                                reloadTick++;
                              });
                            }
                          },
                          child: Text('retry-text'.i18n()),
                        ),
                        const SizedBox(width: 8),
                        AiDiagnoseButton(errorMessage: failure.details),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        // By default, show a loading spinner.
        //
        // `Expanded`, like the data and error branches: a bare `Padding` has
        // no height to centre within, so the spinner drew at y=90 and the
        // error that replaced it at y=420 — 330 px of jump when the load
        // resolved (audit LN-20).
        return Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ProgressRing(),
                if (remoteEnabled) ...[
                  const SizedBox(height: 10),
                  Text('connectingtoremote-text'.i18n([
                    remoteTarget.isEmpty ? 'remotenotset-text'.i18n() : remoteTarget
                  ])),
                  const SizedBox(height: 12),
                  // `getSshClientOptions` sets no ConnectTimeout, so an
                  // unreachable host holds this for the OS default TCP
                  // timeout. Going back to the local WSL is the one action
                  // that ends the wait, and it is the same remedy the error
                  // branch offers.
                  Button(
                    key: const ValueKey('test-list-loading-use-local'),
                    onPressed: () async {
                      await prefs.setBool('UseRemoteWSL', false);
                      if (mounted) {
                        setState(() {
                          reloadTick++;
                        });
                      }
                    },
                    child: Text('uselocalwsl-text'.i18n()),
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
