import 'package:fluent_ui/fluent_ui.dart';
import 'package:localization/localization.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:window_manager/window_manager.dart';
import 'package:wsl2distromanager/components/constants.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/dialogs/create_dialog.dart';
import 'package:wsl2distromanager/dialogs/info_dialog.dart';
import 'package:wsl2distromanager/screens/actions_screen.dart';
import 'package:wsl2distromanager/screens/settings_screen.dart';
import 'package:wsl2distromanager/theme.dart';

import 'package:flutter_acrylic/flutter_acrylic.dart' as flutter_acrylic;

class Navbar extends StatefulWidget {
  const Navbar({
    Key? key,
    required this.title,
    required this.child,
  }) : super(key: key);
  final String title;
  final Widget child;

  @override
  State<Navbar> createState() => _NavbarState();
}

bool hasPushed = false;

class _NavbarState extends State<Navbar> {
  bool customTheme = false;
  int index = 0;
  static bool firstStart = true;
  static bool locked = false;
  // Fix for double click on Navigation Pane
  void lockFor500Ms({required Function onDone}) {
    if (locked) return;
    locked = true;
    onDone();
    Future.delayed(const Duration(milliseconds: 500), () {
      locked = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppTheme(),
      builder: (context, _) {
        final appTheme = context.watch<AppTheme>();
        // Is dark mode
        var brightness = MediaQuery.of(context).platformBrightness;
        bool isDarkMode = brightness == Brightness.dark;
        Color textColor =
            (!customTheme ? isDarkMode : (appTheme.mode == ThemeMode.dark))
                ? Colors.white
                : Colors.black;
        if (firstStart) {
          firstStart = false;
          // Set theme
          if ((!customTheme && isDarkMode) || appTheme.mode == ThemeMode.dark) {
            AppTheme.themeMode = ThemeMode.dark;
          } else {
            AppTheme.themeMode = ThemeMode.light;
          }
        }
        return FluentApp(
          themeMode: !customTheme ? ThemeMode.system : appTheme.mode,
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
            return navWidget(appTheme, textColor, context, isDarkMode);
          },
          initialRoute: '/',
          routes: {
            '/': (context) => widget.child,
          },
        );
      },
    );
  }

  Directionality navWidget(AppTheme appTheme, Color textColor,
      BuildContext context, bool isDarkMode) {
    return Directionality(
      textDirection: appTheme.textDirection,
      child: NavigationPaneTheme(
        data: NavigationPaneThemeData(
          backgroundColor:
              appTheme.windowEffect != flutter_acrylic.WindowEffect.disabled
                  ? Colors.transparent
                  : null,
        ),
        child: NavigationView(
          pane: NavigationPane(
              displayMode: PaneDisplayMode.auto,
              selected: () {
                // Default to first item as we are using popups for the rest
                return index;
              }(),
              onChanged: (value) {
                // Check if popup of page
                if (value != 0 || value != 2 || value != 3) {
                  // In case we are out of index
                  try {
                    setState(() {
                      index = value;
                    });
                  } catch (e) {
                    // Ignore
                  }
                }
              },
              items: [
                PaneItem(
                  icon: const Icon(FluentIcons.home),
                  title: Text('homepage-text'.i18n(),
                      style: TextStyle(color: textColor)),
                  body: widget.child,
                ),
                PaneItemAction(
                  icon: const Icon(FluentIcons.info),
                  title: Text('about-text'.i18n(),
                      style: TextStyle(color: textColor)),
                  onTap: () {
                    lockFor500Ms(onDone: () {
                      infoDialog(context, prefs, currentVersion);
                    });
                  },
                ),
                PaneItem(
                  icon: const Icon(FluentIcons.settings),
                  title: Text('settings-text'.i18n(),
                      style: TextStyle(color: textColor)),
                  body: const SettingsPage(),
                ),
                PaneItem(
                  icon: const Icon(FluentIcons.settings_add),
                  title: Text('managequickactions-text'.i18n(),
                      style: TextStyle(color: textColor)),
                  body: const QuickPage(),
                ),
                PaneItemAction(
                  icon: const Icon(FluentIcons.add),
                  title: Text('addinstance-text'.i18n(),
                      style: TextStyle(color: textColor)),
                  onTap: () {
                    lockFor500Ms(onDone: () {
                      createDialog(context, () => mounted);
                    });
                  },
                ),
                // Help button
                PaneItemAction(
                  icon: const Icon(FluentIcons.help),
                  title: Text('documentation-text'.i18n(),
                      style: TextStyle(color: textColor)),
                  onTap: () {
                    lockFor500Ms(onDone: () {
                      launchUrlString(
                          'https://github.com/bostrot/wsl2-distro-manager/wiki');
                    });
                  },
                ),
                // Sponsor button
                PaneItemAction(
                  icon: appTheme.mode == ThemeMode.dark
                      ? const Icon(FluentIcons.heart)
                      : const Icon(FluentIcons.heart_fill),
                  title: Text('sponsor-text'.i18n(),
                      // Dark mode color red otherwise white
                      style: TextStyle(
                          color: appTheme.mode == ThemeMode.dark
                              ? textColor
                              : Colors.red)),
                  onTap: () {
                    lockFor500Ms(onDone: () {
                      launchUrlString('https://github.com/sponsors/bostrot');
                    });
                  },
                ),
              ]),
          appBar: NavigationAppBar(
            automaticallyImplyLeading: false,
            title: () {
              return DragToMoveArea(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 20.0),
                    child: Text(widget.title),
                  ),
                ),
              );
            }(),
            actions: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              ToggleSwitch(
                content: const Text('Dark Mode'),
                checked: FluentTheme.of(context).brightness.isDark,
                onChanged: (v) {
                  // Notify settings page to save unsaved changes

                  customTheme = true;
                  if (v) {
                    appTheme.mode = ThemeMode.dark;
                  } else {
                    appTheme.mode = ThemeMode.light;
                  }
                },
              ),
              const WindowButtons(),
            ]),
          ),
        ),
      ),
    );
  }
}

class WindowButtons extends StatelessWidget {
  const WindowButtons({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = FluentTheme.of(context);

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
