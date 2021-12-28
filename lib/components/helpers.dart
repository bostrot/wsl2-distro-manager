import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

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

/// Launch a URL in the default browser
/// @param url: URL to launch
void launchURL(String url) async {
  if (await canLaunch(url)) {
    await launch(url);
  } else {
    throw 'Could not launch $url';
  }
}
