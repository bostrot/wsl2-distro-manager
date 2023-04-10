import 'package:fluent_ui/fluent_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wsl2distromanager/main.dart';

late String language;
late SharedPreferences prefs;

/// Get distro label from item
/// @param item: distro name
/// @returns String
String distroLabel(String item) {
  String? distroName = prefs.getString('DistroName_$item');
  if (distroName == null || distroName == '') {
    distroName = item;
  }
  return distroName;
}

/// Initialize shared preferences
Future initPrefs() async {
  prefs = await SharedPreferences.getInstance();
}

class GlobalVariable {
  static final GlobalKey<RootPageState> root = GlobalKey<RootPageState>();
  static GlobalKey<NavigatorState> infobox = GlobalKey<NavigatorState>();
}
