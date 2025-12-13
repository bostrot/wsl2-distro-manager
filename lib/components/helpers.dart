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
bool hasPushed = false;

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

  final backupFilePath = '$newFilePath.backup';
  final prefsBackupFile = File(backupFilePath);

  if (newFile.existsSync()) {
    bool isCorrupted = false;
    try {
      String content = newFile.readAsStringSync();
      content = fixJsonContent(content);
      if (tryDecodeJson(content) == null) {
        isCorrupted = true;
      }
    } catch (e) {
      debugPrint("Failed to validate new shared_preferences.json: $e");
      isCorrupted = true;
    }

    if (!isCorrupted) {
      // File is valid, create/update backup
      try {
        newFile.copySync(backupFilePath);
      } catch (e) {
        debugPrint("Failed to create preferences backup: $e");
      }
    } else {
      // File is corrupted
      debugPrint('New shared_preferences.json is corrupted.');

      // Backup the corrupted file for analysis (creates .bak)
      backupFile(newFilePath);

      // Try to restore from good backup
      bool restored = false;
      if (prefsBackupFile.existsSync()) {
        try {
          // Validate backup before restoring
          String backupContent = prefsBackupFile.readAsStringSync();
          backupContent = fixJsonContent(backupContent);
          if (tryDecodeJson(backupContent) != null) {
            debugPrint('Restoring preferences from valid backup...');
            prefsBackupFile.copySync(newFilePath);
            restored = true;
          } else {
            debugPrint('Backup file is also corrupted. Ignoring.');
          }
        } catch (e) {
          debugPrint("Failed to validate or restore from backup: $e");
        }
      }

      if (!restored) {
        debugPrint('No valid backup found. Deleting corrupted file...');
        try {
          newFile.deleteSync();
        } catch (e) {
          debugPrint("Failed to delete corrupted preferences file: $e");
        }
      }
    }
  } else if (prefsBackupFile.existsSync()) {
    // File doesn't exist, try to restore from backup if available
    debugPrint('Preferences file missing. Restoring from backup...');
    try {
      // Validate backup before restoring
      String backupContent = prefsBackupFile.readAsStringSync();
      backupContent = fixJsonContent(backupContent);
      if (tryDecodeJson(backupContent) != null) {
        prefsBackupFile.copySync(newFilePath);
      } else {
        debugPrint('Backup file is corrupted. Cannot restore.');
      }
    } catch (e) {
      debugPrint("Failed to restore from backup: $e");
    }
  }

  // Now safely initialize SharedPreferences.
  try {
    prefs = await SharedPreferences.getInstance();
  } catch (e) {
    debugPrint("Error initializing SharedPreferences: $e");
    // Retry once after deleting the file if it exists
    if (newFile.existsSync()) {
      try {
        debugPrint(
            "Retrying SharedPreferences initialization after cleanup...");
        backupFile(newFilePath);
        newFile.deleteSync();
        prefs = await SharedPreferences.getInstance();
      } catch (e2) {
        debugPrint("Fatal error initializing SharedPreferences: $e2");
      }
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
  return getDataPath()..cd('tmp');
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

/// Return the general data path. Templates and downloads are saved here by default.
/// It will be created if it does not exist.
///
/// e.g. C:\WSL2-Distros
SafePath getDataPath() {
  String? path = prefs.getString('DataPath');
  if (path != null && path.isNotEmpty) {
    return SafePath(path);
  }
  // Fallback to DistroPath logic (Root Path)
  String distroPath = prefs.getString('DistroPath') ?? defaultPath;
  return SafePath(distroPath);
}
