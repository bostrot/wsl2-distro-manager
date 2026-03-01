import 'package:win32_registry/win32_registry.dart';

const String lxssBaseKey = r'Software\Microsoft\Windows\CurrentVersion\Lxss';

/// Registry Helper class to get WSL info
class WslRegistry {
  /// Get the distribution path from the registry by [distributionName]
  static String? getDistributionPath(String distributionName) {
    RegistryKey? key;
    try {
      key = Registry.openPath(RegistryHive.currentUser, path: lxssBaseKey);

      // Iterate through subkeys (distributions)
      for (var subkeyName in key.subkeyNames) {
        RegistryKey? subkey;
        try {
          subkey = key.createKey(subkeyName);
          final distroName = subkey.getStringValue('DistributionName');
          if (distroName == distributionName) {
            // Get BasePath
            return subkey.getStringValue('BasePath');
          }
        } catch (e) {
          // Ignore errors opening subkeys
        } finally {
          subkey?.close();
        }
      }
    } catch (e) {
      // Ignore registry errors
    } finally {
      key?.close();
    }
    return null;
  }
}
