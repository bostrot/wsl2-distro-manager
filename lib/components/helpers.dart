import 'package:shared_preferences/shared_preferences.dart';

late String language;
late SharedPreferences prefs;

/// Get distro label from item
/// @param item: distro name
/// @returns String
String distroLabel(String item) {
  String? distroName = prefs.getString('DistroName_' + item);
  if (distroName == null || distroName == '') {
    distroName = item;
  }
  return distroName;
}

/// Initialize shared preferences
Future initPrefs() async {
  prefs = await SharedPreferences.getInstance();
}
