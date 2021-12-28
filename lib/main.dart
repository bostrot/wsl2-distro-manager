import 'package:fluent_ui/fluent_ui.dart';
import 'package:system_theme/system_theme.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:wsl2distromanager/components/analytics.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemTheme.accentInstance.load();
  runApp(MyApp());
  doWhenWindowReady(() {
    final win = appWindow;
    const initialSize = Size(650, 500);
    win.minSize = initialSize;
    win.size = initialSize;
    win.alignment = Alignment.center;
    win.title = "WSL Distro Manager";
    win.show();
  });

  await initPrefs();
  bool? privacyMode = prefs.getBool('privacyMode');
  if (privacyMode != null && privacyMode) {
    plausible.enabled = false;
  }

  // Enable analytics
  plausible.event();
}

class MyApp extends StatelessWidget {
  MyApp({Key? key}) : super(key: key);
  ThemeData themeData = ThemeData();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: SystemTheme.darkMode,
      builder: (BuildContext context, AsyncSnapshot<bool> darkMode) {
        if (darkMode.hasData) {
          if (darkMode.data == false) {
            // lightmode
            themeData = ThemeData(
              activeColor: Colors.black,
              accentColor: SystemTheme.accentInstance.accent.toAccentColor(),
              brightness: Brightness.light, // or Brightness.dark
            );
          } else {
            // darkmode
            themeData = ThemeData(
              activeColor: Colors.white,
              accentColor: SystemTheme.accentInstance.accent.toAccentColor(),
              brightness: Brightness.dark, // or Brightness.dark
            );
          }
          return FluentApp(
            title: 'WSL2 Distro Manager by Bostrot',
            theme: themeData,
            home: MyHomePage(
              title: 'WSL Distro Manager by Bostrot',
              themeData: themeData,
            ),
            debugShowCheckedModeBanner: false,
          );
        } else if (darkMode.hasError) {
          return const FluentApp(
            home: Center(child: Text('An error occured. Please report this.')),
          );
        } else {
          return const FluentApp(home: Text(''));
        }
      },
    );
  }
}
