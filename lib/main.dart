import 'package:fluent_ui/fluent_ui.dart' hide Page;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as flutter_acrylic;
import 'package:go_router/go_router.dart';
import 'package:localization/localization.dart';
import 'package:provider/provider.dart';
import 'package:system_theme/system_theme.dart';
import 'package:url_launcher/link.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';
import 'package:wsl2distromanager/api/quick_actions.dart';
import 'package:wsl2distromanager/api/wsl.dart';
import 'package:wsl2distromanager/components/constants.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/components/notify.dart';
import 'package:wsl2distromanager/dialogs/create_dialog.dart';
import 'package:wsl2distromanager/dialogs/info_dialog.dart';
import 'package:wsl2distromanager/screens/actions_screen.dart';
import 'package:wsl2distromanager/screens/home_screen.dart';
import 'package:wsl2distromanager/screens/settings_screen.dart';

import 'theme.dart';

const String appTitle = "WSL Manager v$currentVersion";

/// Checks if the current environment is a desktop environment.
bool get isDesktop {
  if (kIsWeb) return false;
  return [
    TargetPlatform.windows,
    TargetPlatform.linux,
    TargetPlatform.macOS,
  ].contains(defaultTargetPlatform);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // if it's not on the web, windows or android, load the accent color
  if (!kIsWeb &&
      [
        TargetPlatform.windows,
        TargetPlatform.android,
      ].contains(defaultTargetPlatform)) {
    SystemTheme.accentColor.load();
  }

  if (isDesktop) {
    await flutter_acrylic.Window.initialize();
    await flutter_acrylic.Window.hideWindowControls();
    await WindowManager.instance.ensureInitialized();
    windowManager.waitUntilReadyToShow().then((_) async {
      await windowManager.setTitleBarStyle(
        TitleBarStyle.hidden,
        windowButtonVisibility: false,
      );
      await windowManager.setMinimumSize(const Size(700, 600));
      await windowManager.show();
      await windowManager.setPreventClose(true);
      await windowManager.setSkipTaskbar(false);
    });
  }

  runApp(const WSLManager());
}

class WSLManager extends StatelessWidget {
  const WSLManager({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    LocalJsonLocalization.delegate.directories = ['lib/i18n'];
    return ChangeNotifierProvider(
      create: (_) => AppTheme(),
      builder: (context, _) {
        final appTheme = context.watch<AppTheme>();
        return FluentApp.router(
          title: appTitle,
          themeMode: appTheme.mode,
          debugShowCheckedModeBanner: false,
          color: appTheme.color,
          darkTheme: FluentThemeData(
            brightness: Brightness.dark,
            accentColor: appTheme.color,
            visualDensity: VisualDensity.standard,
            focusTheme: FocusThemeData(
              glowFactor: is10footScreen() ? 2.0 : 0.0,
            ),
          ),
          theme: FluentThemeData(
            accentColor: appTheme.color,
            visualDensity: VisualDensity.standard,
            focusTheme: FocusThemeData(
              glowFactor: is10footScreen() ? 2.0 : 0.0,
            ),
          ),
          locale: appTheme.locale,
          localeResolutionCallback: (locale, supportedLocales) {
            if (locale == null) {
              return const Locale('en', '');
            }
            language = locale.toLanguageTag();
            if (supportedLocales.contains(locale)) {
              return locale;
            }

            // Custom matching for chinese (simplified and traditional)
            if (language.toLowerCase().contains("hans")) {
              return const Locale('zh', 'CN');
            } else if (language.toLowerCase().contains("hant")) {
              return const Locale('zh', 'TW');
            } else if (locale.languageCode == "zh") {
              return const Locale('zh', 'CN');
            }

            // No exact match, try language only
            final Locale lang = Locale(locale.languageCode, '');
            if (supportedLocales.contains(lang)) {
              return lang;
            }

            // default language
            return const Locale('en', '');
          },
          localizationsDelegates: [
            LocalJsonLocalization.delegate,
          ],
          supportedLocales: const [
            Locale('en', ''), // English, no country code
            Locale('de', ''), // German, no country code
            Locale('pt', ''), // Portuguese, no country code
            Locale('zh', ''), // Chinese, simplified
            Locale('zh', 'TW'), // Chinese, taiwan (traditional)
            Locale('zh', 'HK'), // Chinese, hongkong (traditional)
          ],
          builder: (context, child) {
            return Directionality(
              textDirection: appTheme.textDirection,
              child: NavigationPaneTheme(
                data: NavigationPaneThemeData(
                  backgroundColor: appTheme.windowEffect !=
                          flutter_acrylic.WindowEffect.disabled
                      ? Colors.transparent
                      : null,
                ),
                child: child!,
              ),
            );
          },
          routeInformationParser: router.routeInformationParser,
          routerDelegate: router.routerDelegate,
          routeInformationProvider: router.routeInformationProvider,
        );
      },
    );
  }
}

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

  // Global runner
  dynamic runner(dynamic func) {
    return func;
  }

  final viewKey = GlobalKey(debugLabel: 'Navigation View Key');
  final searchKey = GlobalKey(debugLabel: 'Search Bar Key');
  final searchFocusNode = FocusNode();
  final searchController = TextEditingController();

  final List<NavigationPaneItem> originalItems = [
    PaneItem(
      key: const Key('/'),
      icon: const Icon(FluentIcons.home),
      title: Text('homepage-text'.i18n()),
      body: const SizedBox.shrink(),
      onTap: () {
        if (router.location != '/') router.pushNamed('home');
      },
    ),
    PaneItem(
      key: const Key('/quickactions'),
      icon: const Icon(FluentIcons.settings_add),
      title: Text('managequickactions-text'.i18n()),
      body: const SizedBox.shrink(),
      onTap: () {
        if (router.location != '/quickactions') {
          router.pushNamed('quickactions');
        }
      },
    ),
    PaneItem(
      key: const Key('/addinstance'),
      icon: const Icon(FluentIcons.add),
      title: Text('addinstance-text'.i18n()),
      body: const SizedBox.shrink(),
      onTap: () {
        createDialog();
      },
    ),
  ];
  final List<NavigationPaneItem> footerItems = [
    _LinkPaneItemAction(
      icon: const Icon(FluentIcons.heart),
      title: Text('sponsor-text'.i18n()),
      link: 'https://github.com/sponsors/bostrot',
      body: const SizedBox.shrink(),
    ),
    PaneItemSeparator(),
    PaneItem(
      key: const Key('/settings'),
      icon: const Icon(FluentIcons.settings),
      title: Text('settings-text'.i18n()),
      body: const SizedBox.shrink(),
      onTap: () {
        if (router.location != '/settings') router.pushNamed('settings');
      },
    ),
    _LinkPaneItemAction(
      icon: const Icon(FluentIcons.help),
      title: Text('documentation-text'.i18n()),
      link: 'https://github.com/bostrot/wsl2-distro-manager/wiki',
      body: const SizedBox.shrink(),
    ),
    PaneItem(
      key: const Key('/about'),
      icon: const Icon(FluentIcons.info),
      title: Text('about-text'.i18n()),
      body: const SizedBox.shrink(),
      onTap: () {
        infoDialog(prefs, currentVersion);
      },
    ),
  ];

  @override
  void initState() {
    windowManager.addListener(this);

    // Check updates
    App app = App();
    app.checkUpdate(currentVersion).then((updateUrl) {
      if (updateUrl != '') {
        statusMsg('',
            useWidget: true,
            widget: RichText(
                text: TextSpan(children: [
              TextSpan(
                  text: '${'newversion-text'.i18n()} ',
                  style: const TextStyle(fontSize: 14.0)),
              TextSpan(
                  text: '${'downloadnow-text'.i18n()} ',
                  style: TextStyle(
                      color: Colors.purple,
                      fontSize: 14.0,
                      fontWeight: FontWeight.bold),
                  recognizer: TapGestureRecognizer()
                    ..onTap = () => launchUrl(Uri.parse(updateUrl))),
              TextSpan(
                  text: '${'orcheck-text'.i18n()} ',
                  style: const TextStyle(fontSize: 14.0)),
              TextSpan(
                  text: '${'windowsstore-text'.i18n()} ',
                  style: TextStyle(
                      color: Colors.purple,
                      fontSize: 14.0,
                      fontWeight: FontWeight.bold),
                  recognizer: TapGestureRecognizer()
                    ..onTap = () => launchUrl(Uri.parse(windowsStoreUrl))),
            ])));
      }
    });

    // Check motd
    app.checkMotd().then((String motd) {
      statusMsg(motd, leadingIcon: false);
    });

    // Call constructor to initialize
    Notify();
    Notify.message = statusMsg;

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
    final location = router.location;
    int indexOriginal = originalItems
        .toList()
        .indexWhere((element) => element.key == Key(location));

    if (indexOriginal == -1) {
      int indexFooter = footerItems
          .toList()
          .indexWhere((element) => element.key == Key(location));
      if (indexFooter == -1) {
        return 0;
      }
      indexFooter--;
      return originalItems.toList().length + indexFooter;
    } else {
      return indexOriginal;
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = FluentLocalizations.of(context);

    final appTheme = context.watch<AppTheme>();
    if (widget.shellContext != null) {
      if (router.canPop() == false) {
        setState(() {});
      }
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
            return const Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(appTitle),
            );
          }
          return const DragToMoveArea(
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(appTitle),
            ),
          );
        }(),
        actions: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8.0),
            child: ToggleSwitch(
              content: const Text('Dark Mode'),
              checked: FluentTheme.of(context).brightness.isDark,
              onChanged: (v) {
                if (v) {
                  appTheme.mode = ThemeMode.dark;
                } else {
                  appTheme.mode = ThemeMode.light;
                }
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
            children: [widget.child, statusBuilder()],
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
      onOpenSearch: () {
        searchFocusNode.requestFocus();
      },
    );
  }

  String status = '';
  bool loading = false;
  bool statusLeading = true;
  Widget statusWidget = const Text('');
  void statusMsg(
    String msg, {
    InfoBarSeverity severity = InfoBarSeverity.info,
    bool loading = false,
    bool useWidget = false,
    bool leadingIcon = true,
    Widget widget = const Text(''),
  }) {
    if (!mounted) {
      return;
    }
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
  }

  Widget statusBuilder() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(left: 50.0, bottom: 10.0),
        child: AnimatedOpacity(
          opacity: status != '' ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 500),
          child: InfoBar(
            style: InfoBarThemeData(
              decoration: (severity) {
                switch (severity) {
                  case InfoBarSeverity.info:
                    return BoxDecoration(
                      color: AppTheme().backgroundColor.darker,
                      borderRadius: BorderRadius.circular(4.0),
                    );
                  case InfoBarSeverity.warning:
                    return BoxDecoration(
                      color: AppTheme().backgroundColor.darker,
                      borderRadius: BorderRadius.circular(4.0),
                    );
                  case InfoBarSeverity.error:
                    return BoxDecoration(
                      color: AppTheme().backgroundColor.darker,
                      borderRadius: BorderRadius.circular(4.0),
                    );
                  case InfoBarSeverity.success:
                    return BoxDecoration(
                      color: AppTheme().backgroundColor.darker,
                      borderRadius: BorderRadius.circular(4.0),
                    );
                    break;
                }
              },
            ),
            title: status == 'WIDGET'
                ? SingleChildScrollView(
                    scrollDirection: Axis.horizontal, child: statusWidget)
                : Text(
                    status,
                    maxLines: 1,
                  ),
            action: loading
                ? const SizedBox(
                    width: 20.0, height: 20.0, child: ProgressRing())
                : const Text(''),
            severity: InfoBarSeverity.info,
            onClose: () {
              // Dismiss the info bar
              setState(() {
                status = '';
              });
            },
          ),
        ),
      ),
    );
  }

  @override
  void onWindowClose() async {
    // TODO: implement onWindowClose
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

class _LinkPaneItemAction extends PaneItem {
  _LinkPaneItemAction({
    required super.icon,
    required this.link,
    required super.body,
    super.title,
  }) : super();

  final String link;

  @override
  Widget build(
    BuildContext context,
    bool selected,
    VoidCallback? onPressed, {
    PaneDisplayMode? displayMode,
    bool showTextOnTop = true,
    bool? autofocus,
    int? itemIndex,
  }) {
    return Link(
      uri: Uri.parse(link),
      builder: (context, followLink) => super.build(
        context,
        selected,
        followLink,
        displayMode: displayMode,
        showTextOnTop: showTextOnTop,
        itemIndex: itemIndex,
        autofocus: autofocus,
      ),
    );
  }
}

final rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();
final router = GoRouter(
  navigatorKey: rootNavigatorKey,
  routes: [
    ShellRoute(
      navigatorKey: _shellNavigatorKey,
      builder: (context, state, child) {
        return RootPage(
          key: GlobalVariable.root,
          shellContext: _shellNavigatorKey.currentContext,
          state: state,
          child: child,
        );
      },
      routes: [
        /// Home
        GoRoute(
          path: '/',
          name: 'home',
          builder: (context, state) => const HomePage(
            title: "WSL Manager",
          ),
        ),

        /// Settings
        GoRoute(
          path: '/settings',
          name: 'settings',
          builder: (context, state) => const SettingsPage(),
        ),

        /// Quick Actions
        GoRoute(
          path: '/quickactions',
          name: 'quickactions',
          builder: (context, state) => const QuickPage(),
        ),
      ],
    ),
  ],
);
