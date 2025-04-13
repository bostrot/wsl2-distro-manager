import 'dart:convert';
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

/// Utility: Validate JSON content. Returns the decoded JSON on success,
/// or `null` if the content is not valid JSON.
dynamic tryDecodeJson(String content) {
  try {
    return json.decode(content);
  } catch (e) {
    debugPrint('JSON decode failed: $e');
    return null;
  }
}

/// Utility: Attempts to “fix” the content by trimming unexpected characters.
/// Returns the fixed JSON string if successful, or the original if not.
String fixJsonContent(String content) {
  String trimmed = content.trim();
  // Quick check: if it already starts with valid JSON tokens, use it.
  if ((trimmed.startsWith('{') || trimmed.startsWith('[')) &&
      (trimmed.endsWith('}') || trimmed.endsWith(']'))) {
    return trimmed;
  }
  // Otherwise try removing first and/or last character
  if (trimmed.length > 1) {
    String candidate = trimmed.substring(1);
    if (tryDecodeJson(candidate) != null) return candidate;
    candidate = trimmed.substring(0, trimmed.length - 1);
    if (tryDecodeJson(candidate) != null) return candidate;
  }
  // Return original in worst case.
  return content;
}

/// Backs up a file by copying it to a new file with a `.bak` suffix.
void backupFile(String path) {
  try {
    File(path).copySync('$path.bak');
    debugPrint('Backed up file: $path to $path.bak');
  } catch (e) {
    debugPrint('Failed to backup file: $e');
  }
}

/// Initialize shared preferences and perform any necessary file migration
/// or repair operations.
Future initPrefs() async {
  // Define app paths for migration.
  final appData = Platform.environment['APPDATA']!;
  final oldSafePath = SafePath(appData)
    ..cd('com.bostrot')
    ..cd('WSL Manager');
  final newSafePath = SafePath(appData)
    ..cd('com.bostrot')
    ..cd('WSL Distro Manager');

  final oldFilePath = oldSafePath.file('shared_preferences.json');
  final newFilePath = newSafePath.file('shared_preferences.json');
  final oldFile = File(oldFilePath);
  final newFile = File(newFilePath);

  // Migration: If the old file exists, try to incorporate its contents.
  if (oldFile.existsSync()) {
    try {
      String oldContent = oldFile.readAsStringSync();
      // Fix the content if there are small corruption issues.
      oldContent = fixJsonContent(oldContent);
      final oldJson = tryDecodeJson(oldContent);
      if (oldJson == null) {
        // Could not decode old file, back it up and delete.
        backupFile(oldFilePath);
        oldFile.deleteSync();
      } else {
        // If a new file exists, merge the data.
        if (newFile.existsSync() && newFile.readAsStringSync().isNotEmpty) {
          String newContent = newFile.readAsStringSync();
          newContent = fixJsonContent(newContent);
          final newJson = tryDecodeJson(newContent);
          if (newJson != null) {
            // For simplicity, assume both files contain maps.
            if (newJson is Map && oldJson is Map) {
              // Merge: old data supplements new data.
              newJson.addAll(oldJson);
            }
            // Backup new file, then write merged contents.
            backupFile(newFilePath);
            newFile.writeAsStringSync(json.encode(newJson),
                mode: FileMode.writeOnly);
            // Backup and remove old file after migration.
            backupFile(oldFilePath);
            oldFile.deleteSync();
          }
        }
      }
    } catch (e) {
      debugPrint('Error during old file migration: $e');
    }
  }

  // Validate the new shared_preferences file.
  if (newFile.existsSync()) {
    try {
      String content = newFile.readAsStringSync();
      content = fixJsonContent(content);
      if (tryDecodeJson(content) == null) {
        // If new file is invalid, back it up and delete.
        debugPrint('New shared_preferences.json is corrupted. Repairing...');
        backupFile(newFilePath);
        newFile.deleteSync();
      }
    } catch (e) {
      debugPrint("Failed to validate new shared_preferences.json: $e");
    }
  }

  // Now safely initialize SharedPreferences.
  try {
    prefs = await SharedPreferences.getInstance();
  } catch (e) {
    debugPrint("Error initializing SharedPreferences: $e");
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
