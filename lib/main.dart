import 'package:fluent_ui/fluent_ui.dart' hide Page;
import 'package:flutter/foundation.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as flutter_acrylic;
import 'package:localization/localization.dart';
import 'package:provider/provider.dart';
import 'package:system_theme/system_theme.dart';
import 'package:window_manager/window_manager.dart';
import 'package:wsl2distromanager/components/constants.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/components/logging.dart';
import 'package:wsl2distromanager/nav/router.dart';

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
      await windowManager.setMinimumSize(const Size(574, 450));
      await windowManager.setSize(const Size(700, 500));
      await windowManager.show();
      await windowManager.setPreventClose(true);
      await windowManager.setSkipTaskbar(false);
    });
  }

  // Init logging
  initLogging();
  initPrefs();

  // Error logging
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    logError(details.exception, details.stack, details.library);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    logError(error, stack, null);
    return true;
  };

  // Init app
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
        // Wait for prefs to be initialized
        while (!initialized) {}
        final appTheme = context.watch<AppTheme>();
        var selectedLang = prefs.getString('language');
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
              glowFactor: is10footScreen(context) ? 2.0 : 0.0,
            ),
          ),
          theme: FluentThemeData(
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
              if (language == "zh") {
                return const Locale('zh', 'CN');
              }
              return Locale(selectedLang);
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
