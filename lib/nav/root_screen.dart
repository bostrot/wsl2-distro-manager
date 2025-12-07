import 'dart:async';
import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart' hide Page;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:wsl2distromanager/components/notify.dart';
import 'package:wsl2distromanager/dialogs/bug_dialog.dart';
import 'package:wsl2distromanager/main.dart';
import 'package:wsl2distromanager/nav/init.dart';
import 'package:wsl2distromanager/nav/panelist.dart';
import 'package:wsl2distromanager/nav/router.dart';
import 'package:wsl2distromanager/theme.dart';

class RootPage extends StatefulWidget {
  const RootPage({
    Key? key,
    required this.child,
    required this.shellContext,
    required this.state,
  }) : super(key: key);

  final Widget child;
  final BuildContext? shellContext;
  final GoRouterState state;

  @override
  State<RootPage> createState() => RootPageState();
}

class RootPageState extends State<RootPage> with WindowListener {
  bool value = false;

  dynamic runner(dynamic func) {
    return func;
  }

  final viewKey = GlobalKey(debugLabel: 'Navigation View Key');
  final searchKey = GlobalKey(debugLabel: 'Search Bar Key');
  final searchFocusNode = FocusNode();
  final searchController = TextEditingController();

  String status = '';
  bool loading = false;
  bool statusLeading = true;
  Widget statusWidget = const Text('');
  Timer? _messageTimer;

  void statusMsg(
    String msg, {
    Duration? duration,
    InfoBarSeverity severity = InfoBarSeverity.info,
    bool loading = false,
    bool useWidget = false,
    bool leadingIcon = true,
    Widget widget = const Text(''),
  }) {
    if (!mounted) return;

    _messageTimer?.cancel();

    if (useWidget) {
      setState(() {
        status = 'WIDGET';
        this.loading = loading;
        statusWidget = widget;
        statusLeading = leadingIcon;
      });
    } else {
      setState(() {
        status = msg;
        this.loading = loading;
        statusLeading = leadingIcon;
      });
    }

    if (duration != null) {
      _messageTimer = Timer(duration, () {
        if (mounted) {
          setState(() {
            status = '';
            this.loading = false;
          });
        }
      });
    }
  }

  @override
  void initState() {
    windowManager.addListener(this);
    initRoot(statusMsg);
    super.initState();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    searchController.dispose();
    searchFocusNode.dispose();
    super.dispose();
  }

  int _calculateSelectedIndex(BuildContext context) {
    final path = widget.state.uri.path;
    int indexOriginal =
        originalItems.indexWhere((element) => element.key == Key(path));

    if (indexOriginal == -1) {
      int indexFooter =
          footerItems.indexWhere((element) => element.key == Key(path));
      if (indexFooter == -1) return 0;
      indexFooter--;
      return originalItems.length + indexFooter;
    } else {
      return indexOriginal;
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = FluentLocalizations.of(context);
    final appTheme = context.watch<AppTheme>();

    if (widget.shellContext != null && !router.canPop()) {
      setState(() {});
    }

    return NavigationView(
      key: viewKey,
      appBar: NavigationAppBar(
        automaticallyImplyLeading: false,
        leading: () {
          final enabled = widget.shellContext != null && router.canPop();
          final onPressed = enabled
              ? () {
                  if (router.canPop()) {
                    context.pop();
                    setState(() {});
                  }
                }
              : null;

          return NavigationPaneTheme(
            data: NavigationPaneTheme.of(context).merge(NavigationPaneThemeData(
              unselectedIconColor: ButtonState.resolveWith((states) {
                if (states.isDisabled) {
                  return ButtonThemeData.buttonColor(context, states);
                }
                return ButtonThemeData.uncheckedInputColor(
                  FluentTheme.of(context),
                  states,
                ).basedOnLuminance();
              }),
            )),
            child: Builder(
              builder: (context) => PaneItem(
                icon: const Center(child: Icon(FluentIcons.back, size: 12.0)),
                title: Text(localizations.backButtonTooltip),
                body: const SizedBox.shrink(),
                enabled: enabled,
              ).build(
                context,
                false,
                onPressed,
                displayMode: PaneDisplayMode.compact,
              ),
            ),
          );
        }(),
        title: () {
          if (kIsWeb) {
            return Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(appTitle),
            );
          }
          return DragToMoveArea(
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(appTitle),
            ),
          );
        }(),
        actions: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          Padding(
              padding: const EdgeInsetsDirectional.only(end: 8.0),
              child: IconButton(
                icon: const Icon(FluentIcons.bug),
                onPressed: () => bugDialog(),
              )),
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8.0),
            child: ToggleSwitch(
              content: const Text('Dark Mode'),
              checked: FluentTheme.of(context).brightness.isDark,
              onChanged: (v) {
                appTheme.mode = v ? ThemeMode.dark : ThemeMode.light;
              },
            ),
          ),
          if (!kIsWeb) const WindowButtons(),
        ]),
      ),
      paneBodyBuilder: (item, child) {
        final name =
            item?.key is ValueKey ? (item!.key as ValueKey).value : null;
        return FocusTraversalGroup(
          key: ValueKey('body$name'),
          child: Stack(
            children: [
              widget.child,
              statusBuilder(status, statusWidget, loading, () {
                setState(() => status = '');
              }),
            ],
          ),
        );
      },
      pane: NavigationPane(
        selected: _calculateSelectedIndex(context),
        displayMode: appTheme.displayMode,
        indicator: () {
          switch (appTheme.indicator) {
            case NavigationIndicators.end:
              return const EndNavigationIndicator();
            case NavigationIndicators.sticky:
            default:
              return const StickyNavigationIndicator();
          }
        }(),
        items: originalItems,
        footerItems: footerItems,
      ),
      onOpenSearch: () => searchFocusNode.requestFocus(),
    );
  }

  @override
  void onWindowClose() async {
    SystemNavigator.pop();
    exit(0);
  }
}

class WindowButtons extends StatelessWidget {
  const WindowButtons({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);

    return SizedBox(
      width: 138,
      height: 50,
      child: WindowCaption(
        brightness: theme.brightness,
        backgroundColor: Colors.transparent,
      ),
    );
  }
}
