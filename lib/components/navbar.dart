import 'package:fluent_ui/fluent_ui.dart';
import 'package:localization/localization.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:wsl2distromanager/components/constants.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/components/notify.dart';
import 'package:wsl2distromanager/dialogs/create_dialog.dart';
import 'package:wsl2distromanager/dialogs/info_dialog.dart';
import 'package:wsl2distromanager/theme.dart';
import 'constants.dart';
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
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppTheme(),
      builder: (context, _) {
        final appTheme = context.watch<AppTheme>();
        return FluentApp(
          themeMode: !customTheme ? ThemeMode.system : appTheme.mode,
          debugShowCheckedModeBanner: false,
          color: appTheme.color,
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            accentColor: appTheme.color,
            visualDensity: VisualDensity.standard,
            focusTheme: FocusThemeData(
              glowFactor: is10footScreen() ? 2.0 : 0.0,
            ),
          ),
          theme: ThemeData(
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
            Locale lang = Locale(locale.languageCode, '');
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
            Locale('zh', ''), // Chinese, no country code
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
                child: NavigationView(
                  pane: NavigationPane(items: [
                    PaneItemAction(
                      icon: const Icon(FluentIcons.info),
                      title: Text('about-text'.i18n()),
                      onTap: () {
                        infoDialog(
                            context, prefs, Notify.message, currentVersion);
                      },
                    ),
                    PaneItemAction(
                      icon: const Icon(FluentIcons.settings),
                      title: Text('settings-text'.i18n()),
                      onTap: () {
                        Navigator.popAndPushNamed(context, '/settings');
                      },
                    ),
                    PaneItemAction(
                      icon: const Icon(FluentIcons.settings_add),
                      title: Text('managequickactions-text'.i18n()),
                      onTap: () {
                        Navigator.popAndPushNamed(context, '/actions');
                      },
                    ),
                    PaneItemAction(
                      icon: const Icon(FluentIcons.add),
                      title: Text('addinstance-text'.i18n()),
                      onTap: () {
                        createDialog(context, () => mounted, Notify.message);
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
                    actions: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          ToggleSwitch(
                            content: const Text('Dark Mode'),
                            checked: FluentTheme.of(context).brightness.isDark,
                            onChanged: (v) {
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
                  content: child!,
                ),
              ),
            );
          },
          initialRoute: '/',
          routes: {
            '/': (context) => widget.child,
          },
        );
      },
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
