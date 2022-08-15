import 'package:fluent_ui/fluent_ui.dart';
import 'package:localization/localization.dart';
import 'package:system_theme/system_theme.dart';
import 'package:window_manager/window_manager.dart';
import 'package:wsl2distromanager/components/analytics.dart';
import 'package:wsl2distromanager/components/constants.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/components/navbar.dart';
import 'package:wsl2distromanager/components/theme.dart';
import 'package:wsl2distromanager/screens/home_screen.dart';

void main() async {
  SystemTheme.accentColor.load();
  WidgetsFlutterBinding.ensureInitialized();

  // Must add this line.
  await windowManager.ensureInitialized();

  WindowOptions windowOptions = const WindowOptions(
    minimumSize: Size(400, 400),
    size: Size(800, 600),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const WSLDistroManager());

  await initPrefs();
  bool? privacyMode = prefs.getBool('privacyMode');
  if (privacyMode != null && privacyMode) {
    plausible.enabled = false;
  }
}

class WSLDistroManager extends StatefulWidget {
  const WSLDistroManager({Key? key}) : super(key: key);

  @override
  State<WSLDistroManager> createState() => _WSLDistroManagerState();
}

class _WSLDistroManagerState extends State<WSLDistroManager> {
  @override
  Widget build(BuildContext context) {
    LocalJsonLocalization.delegate.directories = ['lib/i18n'];

    return FluentApp(
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
      ],
      home: const Navbar(
        title: "$title $currentVersion",
        child: HomePage(title: 'WSL Distro Manager by Bostrot'),
      ),
    );
  }
}
