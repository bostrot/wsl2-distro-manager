import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wsl2distromanager/api/safe_paths.dart';
import 'package:wsl2distromanager/api/wsl.dart';
import 'package:wsl2distromanager/components/constants.dart';
import 'package:wsl2distromanager/nav/root_screen.dart';

late String language;
late SharedPreferences prefs;
bool initialized = false;

/// Get distro label from [item].
String distroLabel(String item) {
  String? distroName = prefs.getString('DistroName_$item');
  if (distroName == null || distroName == '') {
    distroName = item;
  }
  return distroName;
}

/// Replace special characters in [name] with underscores.
String replaceSpecialChars(String name) {
  return name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
}

/// Initialize shared preferences
Future initPrefs() async {
  prefs = await SharedPreferences.getInstance();

  // Fix for older versions and move the shared_preferences.json file
  var oldPath = (SafePath(Platform.environment['APPDATA']!)
        ..cd('com.bostrot')
        ..cd('WSL Manager'))
      .file('shared_preferences.json');
  if (File(oldPath).existsSync()) {
    var oldContent = File(oldPath).readAsStringSync();
    oldContent = oldContent.substring(1, oldContent.length);

    var newPath = (SafePath(Platform.environment['APPDATA']!)
          ..cd('com.bostrot')
          ..cd('WSL Distro Manager'))
        .file('shared_preferences.json');

    if (File(newPath).existsSync() && File(newPath).readAsStringSync() != '') {
      var newContent = File(newPath).readAsStringSync();
      newContent = newContent.substring(0, newContent.length - 1);
      newContent = '$newContent,$oldContent';
      // Backup old file
      File(newPath).copySync('$newPath.bak');
      File(newPath).deleteSync();
      // Write new content
      File(newPath).writeAsStringSync(newContent, mode: FileMode.writeOnly);
      File(oldPath).copySync('$oldPath.bak');
      File(oldPath).deleteSync();
    }
  }

  initialized = true;
}

/// Global variables for global context access.
class GlobalVariable {
  static final GlobalKey<RootPageState> root = GlobalKey<RootPageState>();
  static GlobalKey<NavigatorState> infobox = GlobalKey<NavigatorState>();
  static Instances? initialSnapshot;
}

/// Return the general distro path. Distros are saved here by default.
/// It will be created if it does not exist.
///
/// e.g. C:\WSL2-Distros\distros
SafePath getDistroPath() {
  String path = prefs.getString('DistroPath') ?? defaultPath;
  return SafePath(path)..cd('distros');
}

/// Get the tmp folder path. This is used for the download of docker layers.
/// It will be created if it does not exist.
///
/// e.g. C:\WSL2-Distros\tmp
SafePath getTmpPath() {
  return getDistroPath()
    ..cdUp()
    ..cd('tmp');
}

/// Get the instance path for the [name] instance.
/// It will be created if it does not exist.
///
/// e.g. C:\WSL2-Distros\ubuntu
SafePath getInstancePath(String name) {
  String? instanceLocation = prefs.getString('Path_$name');
  if (instanceLocation != null && instanceLocation.isNotEmpty) {
    // Fix path for older versions
    var safePath = SafePath(instanceLocation);
    prefs.setString('Path_$name', safePath.path);
    return safePath;
  }
  return getDistroPath()
    ..cdUp()
    ..cd(name);
}

/// Get instance size for [name] instance.
String getInstanceSize(String name) {
  var path = getInstancePath(name).file('ext4.vhdx');
  try {
    var size = File(path).lengthSync();

    if (size > 0) {
      var sizeGB = size / 1024 / 1024 / 1024;
      return '${sizeGB.toStringAsFixed(2)} GB';
    } else {
      return '';
    }
  } catch (e) {
    return '';
  }
}

/// Get the wslconfig path
String getWslConfigPath() {
  return SafePath('C:\\Users\\${Platform.environment['USERNAME']}')
      .file('.wslconfig');
}
