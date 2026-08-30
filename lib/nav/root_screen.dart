import 'dart:async';
import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart' hide Page;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:localization/localization.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:wsl2distromanager/api/license_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/components/notify.dart';
import 'package:wsl2distromanager/components/unsaved_changes.dart';
import 'package:wsl2distromanager/dialogs/bug_dialog.dart';
import 'package:wsl2distromanager/main.dart';
import 'package:wsl2distromanager/nav/init.dart';
import 'package:wsl2distromanager/nav/panelist.dart';
import 'package:wsl2distromanager/nav/router.dart';
import 'package:wsl2distromanager/nav/shell_focus.dart';
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

  /// Everything the shell draws — pane, app bar and page — lives in this
  /// scope, so parking focus on it is enough to make Tab work (audit IA-01).
  final shellFocusScope = FocusScopeNode(debugLabel: 'Shell Focus Scope');
  final shellTraversalPolicy = ShellTraversalPolicy();

  String status = '';
  bool loading = false;
  bool statusLeading = true;
  InfoBarSeverity statusSeverity = InfoBarSeverity.info;
  Widget statusWidget = const Text('');
  Timer? _messageTimer;
  DateTime? _statusPostedAt;

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
    _statusPostedAt = DateTime.now();

    setState(() {
      status = useWidget ? 'WIDGET' : msg;
      this.loading = loading;
      statusLeading = leadingIcon;
      statusSeverity = severity;
      if (useWidget) statusWidget = widget;
    });

    // A message with a spinner lives until the operation that owns it replaces
    // it. Everything else expires, so a "Created instance" toast does not
    // follow the user to another screen for the rest of the session.
    final lifetime = duration ?? (loading ? null : notifyDefaultDuration);
    if (lifetime != null) {
      _messageTimer = Timer(lifetime, clearStatus);
    }
  }

  void clearStatus() {
    _messageTimer?.cancel();
    _statusPostedAt = null;
    if (!mounted) return;
    if (status.isEmpty && !loading) return;
    setState(() {
      status = '';
      loading = false;
      statusSeverity = InfoBarSeverity.info;
    });
  }

  @override
  void initState() {
    windowManager.addListener(this);
    // The footer pane item reads the licence state, so it has to rebuild when
    // that changes.
    LicenseManager().addListener(_onLicenseChanged);
    initRoot(statusMsg);
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => adoptKeyboardFocus());
  }

  /// A cold launch — and every return from another window — left the primary
  /// focus on the root scope (audit IA-01). Handing focus to the shell scope
  /// puts traversal back at the top of the cycle.
  void adoptKeyboardFocus() {
    if (!mounted || !shouldAdoptKeyboardFocus()) return;
    shellFocusScope.requestFocus();
  }

  @override
  void didUpdateWidget(covariant RootPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.uri.path == widget.state.uri.path) return;
    // Leaving a screen drops the message that screen put up. The grace window
    // is what keeps a message posted *by* the navigation itself — "Created
    // instance", posted just before the create page returns home — on screen.
    final posted = _statusPostedAt;
    if (posted != null &&
        DateTime.now().difference(posted) < const Duration(seconds: 2)) {
      return;
    }
    if (loading) return;
    clearStatus();
  }

  void _onLicenseChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _messageTimer?.cancel();
    windowManager.removeListener(this);
    LicenseManager().removeListener(_onLicenseChanged);
    searchController.dispose();
    searchFocusNode.dispose();
    shellFocusScope.dispose();
    super.dispose();
  }

  /// fluent_ui addresses the pane by its "effective" items — separators and
  /// headers are dropped from the numbering — so a raw list index does not
  /// line up with what the pane considers selected.
  int _calculateSelectedIndex(BuildContext context) {
    final path = widget.state.uri.path;
    final effective = [...originalItems, ...footerItems]
        .whereType<PaneItem>()
        .where((item) => item is! PaneItemAction)
        .toList();
    final index = effective.indexWhere((item) => item.key == Key(path));
    return index == -1 ? 0 : index;
  }

  @override
  Widget build(BuildContext context) {
    final localizations = FluentLocalizations.of(context);
    final appTheme = context.watch<AppTheme>();

    final navigationView = NavigationView(
      key: viewKey,
      appBar: NavigationAppBar(
        automaticallyImplyLeading: false,
        // Every pane destination is a `go()` on the shell route, so on most
        // screens there is nothing to pop. A permanently disabled arrow was
        // still a tab stop on every screen and still rendered near-white —
        // enabled-looking — in dark (audit IA-03, LN-13), so it is only built
        // when it can actually do something.
        leading: () {
          if (widget.shellContext == null || !router.canPop()) return null;

          return Builder(
            builder: (context) => PaneItem(
              icon: const Center(child: Icon(FluentIcons.back, size: 12.0)),
              title: Text(localizations.backButtonTooltip),
              body: const SizedBox.shrink(),
            ).build(
              context,
              false,
              () async {
                // Back is an exit route like any other, so it asks the screen
                // it is leaving first (audit ST-01).
                if (!await UnsavedChangesGuard.confirmLeave()) return;
                if (!mounted) return;
                if (router.canPop()) {
                  router.pop();
                  setState(() {});
                }
              },
              displayMode: PaneDisplayMode.compact,
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
              child: MergeSemantics(
                child: Tooltip(
                  message: 'reportbug-text'.i18n(),
                  child: IconButton(
                    icon: const Icon(FluentIcons.bug),
                    onPressed: () => bugDialog(),
                  ),
                ),
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
        // A column rather than a stack: overlaid at the bottom, the status bar
        // covered the Create / Cancel row outright on a short window, and the
        // user had no way to move it.
        return ShellBodyScope(
          child: FocusTraversalGroup(
            key: ValueKey('body$name'),
            child: Column(
              children: [
                Expanded(child: widget.child),
                statusBuilder(
                  status,
                  statusWidget,
                  loading,
                  statusLeading,
                  statusSeverity,
                  clearStatus,
                ),
              ],
            ),
          ),
        );
      },
      pane: NavigationPane(
        size: const NavigationPaneSize(openWidth: 220),
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

    // The group has to be above the scope: the sort walks up from the scope
    // node to find the policy that owns it.
    return FocusTraversalGroup(
      policy: shellTraversalPolicy,
      child: FocusScope(node: shellFocusScope, child: navigationView),
    );
  }

  @override
  void onWindowFocus() {
    // Alt-tabbing away and back dropped focus to the root scope, and no key
    // could get it out again (audit IA-01).
    WidgetsBinding.instance.addPostFrameCallback((_) => adoptKeyboardFocus());
  }

  @override
  void onWindowResized() => _saveWindowBounds();

  @override
  void onWindowMoved() => _saveWindowBounds();

  @override
  void onWindowMaximize() => prefs.setBool('WindowMaximized', true);

  @override
  void onWindowUnmaximize() => prefs.setBool('WindowMaximized', false);

  /// Persist the current geometry so the next start reopens where the user
  /// left off. Skipped while maximized, otherwise the restored-down size would
  /// be lost.
  Future<void> _saveWindowBounds() async {
    if (await windowManager.isMaximized()) return;
    final size = await windowManager.getSize();
    final position = await windowManager.getPosition();
    await prefs.setDouble('WindowWidth', size.width);
    await prefs.setDouble('WindowHeight', size.height);
    await prefs.setDouble('WindowLeft', position.dx);
    await prefs.setDouble('WindowTop', position.dy);
  }

  @override
  void onWindowClose() async {
    // `setPreventClose(true)` in main() is what gives a dirty screen the
    // chance to answer here rather than losing the edits to the X (ST-01).
    if (!await UnsavedChangesGuard.confirmLeave()) return;
    await _saveWindowBounds();
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
