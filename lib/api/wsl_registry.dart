import 'package:win32_registry/win32_registry.dart';

const String lxssBaseKey = r'Software\Microsoft\Windows\CurrentVersion\Lxss';

/// Registry Helper class to get WSL info
class WslRegistry {
  /// Get the distribution path from the registry by [distributionName]
  static String? getDistributionPath(String distributionName) {
    try {
      final key = Registry.currentUser..createKey(lxssBaseKey);

      // Iterate through subkeys (distributions)
      for (var subkeyName in key.subkeyNames) {
        try {
          final subkey = key.createKey(subkeyName);
          final distroName = subkey.getStringValue('DistributionName');
          if (distroName == distributionName) {
            // Get BasePath
            final basePath = subkey.getStringValue('BasePath');
            subkey.close();
            key.close();
            return basePath;
          }
          subkey.close();
        } catch (e) {
          // Ignore errors opening subkeys
        }
      }
      key.close();
    } catch (e) {
      // Ignore registry errors
    }
    return null;
  }
}
