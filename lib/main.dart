import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart' hide Page;
import 'package:flutter/foundation.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as flutter_acrylic;
import 'package:localization/localization.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:system_theme/system_theme.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';
import 'package:wsl2distromanager/api/ai_workspace/service.dart';
import 'package:wsl2distromanager/api/execution/broker.dart';
import 'package:wsl2distromanager/api/license_manager.dart';
import 'package:wsl2distromanager/api/mcp/wsl_mcp_service.dart';
import 'package:wsl2distromanager/api/shell.dart';
import 'package:wsl2distromanager/components/constants.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/components/logging.dart';
import 'package:wsl2distromanager/nav/router.dart';

import 'theme.dart';

String appTitle = "WSL Manager v$currentVersion";

/// fluent_ui's NavigationPane only switches to full "open" mode (icons +
/// labels) at widths >= 1008px, so a fresh install starts above that
/// breakpoint.
const Size defaultWindowSize = Size(1180, 780);

/// Reapply the geometry saved by RootPageState, falling back to a centered
/// default window.
Future<void> restoreWindowBounds() async {
  final width = prefs.getDouble('WindowWidth');
  final height = prefs.getDouble('WindowHeight');
  final left = prefs.getDouble('WindowLeft');
  final top = prefs.getDouble('WindowTop');

  await windowManager.setSize(
      width != null && height != null ? Size(width, height) : defaultWindowSize);

  if (left != null && top != null) {
    await windowManager.setPosition(Offset(left, top));
    // A screen that is gone (undocked laptop, changed layout) would leave the
    // window off-screen.
    if (!await _isOnAVisibleScreen()) {
      await windowManager.center();
    }
  } else {
    await windowManager.center();
  }

  if (prefs.getBool('WindowMaximized') ?? false) {
    await windowManager.maximize();
  }
}

Future<bool> _isOnAVisibleScreen() async {
  try {
    final bounds = await windowManager.getBounds();
    final displays = await screenRetriever.getAllDisplays();
    return displays.any((display) {
      final origin = display.visiblePosition ?? Offset.zero;
      final size = display.visibleSize ?? display.size;
      final area = Rect.fromLTWH(origin.dx, origin.dy, size.width, size.height);
      return area.overlaps(bounds);
    });
  } catch (_) {
    return true;
  }
}

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
  final isWindows = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
  final isLinux = !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;

  // if it's not on the web, windows or android, load the accent color
  if (!kIsWeb &&
      [
        TargetPlatform.windows,
        TargetPlatform.android,
      ].contains(defaultTargetPlatform)) {
    SystemTheme.accentColor.load();
  }

  // Init logging
  await initLogging();
  await initPrefs();

  if (isDesktop) {
    await flutter_acrylic.Window.initialize();
    if (isWindows) {
      await flutter_acrylic.Window.hideWindowControls();
    }
    await WindowManager.instance.ensureInitialized();
    await windowManager.waitUntilReadyToShow().then((_) async {
      if (isWindows) {
        await windowManager.setTitleBarStyle(
          TitleBarStyle.hidden,
          windowButtonVisibility: false,
        );
      } else if (isLinux) {
        await windowManager.setAsFrameless();
      }
      await windowManager.setMinimumSize(const Size(700, 500));
      await restoreWindowBounds();
      await windowManager.show();
      await windowManager.setPreventClose(true);
      await windowManager.setSkipTaskbar(false);
    });
  }

  // Create execution broker (local shell by default)
  final Shell shell = ProcessShell();
  final ExecutionBroker executionBroker = ExecutionBroker(shell: shell);

  // Init license manager
  await LicenseManager().init();

  // Restart the MCP server if it was left enabled — external clients need
  // it actually listening.
  final mcpService = WslMcpService();
  if (mcpService.enabled && LicenseManager().isPro) {
    await mcpService.start();
  }

  // Probe AI Workspace in the background so the screen has results by the
  // time it opens. Not awaited; the screen joins this same memoized run.
  final aiWorkspaceService = AiWorkspaceService(broker: executionBroker);
  if (LicenseManager().isPro) {
    unawaited(aiWorkspaceService.ensureInitialized());
  }

  // Error logging
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    logError(details.exception, details.stack, details.library);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    logError(error, stack, null);
    return true;
  };

  // Set version
  await PackageInfo.fromPlatform().then((PackageInfo packageInfo) {
    currentVersion = packageInfo.version;
  });

  // Init app
  runApp(WSLManager(
    executionBroker: executionBroker,
    aiWorkspaceService: aiWorkspaceService,
  ));
}

class WSLManager extends StatelessWidget {
  final ExecutionBroker? executionBroker;
  final AiWorkspaceService? aiWorkspaceService;

  const WSLManager({Key? key, this.executionBroker, this.aiWorkspaceService})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    LocalJsonLocalization.delegate.directories = ['lib/i18n'];
    final broker = executionBroker ?? ExecutionBroker(shell: ProcessShell());
    final workspaceService =
        aiWorkspaceService ?? AiWorkspaceService(broker: broker);
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AppTheme(),
        ),
        Provider<ExecutionBroker>.value(
          value: broker,
        ),
        Provider<AiWorkspaceService>.value(
          value: workspaceService,
        ),
      ],
      builder: (context, _) {
        final appTheme = context.watch<AppTheme>();
        var selectedLang = prefs.getString('language');
        return FluentApp.router(
          title: appTitle,
          themeMode: appTheme.mode,
          debugShowCheckedModeBanner: false,
          color: appTheme.color,
          darkTheme: FluentThemeData(
            tooltipTheme: const TooltipThemeData(
              waitDuration: Duration(milliseconds: 50),
            ),
            brightness: Brightness.dark,
            accentColor: appTheme.color,
            visualDensity: VisualDensity.standard,
            focusTheme: FocusThemeData(
              glowFactor: is10footScreen(context) ? 2.0 : 0.0,
            ),
          ),
          theme: FluentThemeData(
            tooltipTheme: const TooltipThemeData(
              waitDuration: Duration(milliseconds: 50),
            ),
            accentColor: appTheme.color,
            visualDensity: VisualDensity.standard,
            focusTheme: FocusThemeData(
              glowFactor: is10footScreen(context) ? 2.0 : 0.0,
            ),
          ),
          locale: appTheme.locale,
          localeResolutionCallback: (locale, supportedLocales) {
            // Language was set manually
            if (selectedLang != null) {
              language = selectedLang;
              // Stored before the picker used full locale tags.
              if (selectedLang == "zh") {
                return const Locale('zh', 'CN');
              }
              final parts = selectedLang.split('_');
              return parts.length == 2
                  ? Locale(parts[0], parts[1])
                  : Locale(parts[0]);
            }

            if (locale == null) {
              language = 'en';
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
          supportedLocales: supportedLocalesList,
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
