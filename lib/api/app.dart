import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:wsl2distromanager/components/constants.dart';

class App {
  /// Returns an int of the string
  /// '1.2.3' -> 123
  double versionToDouble(String version) {
    return double.tryParse(version
            .toString()
            .replaceAll('v', '')
            .replaceAll('.', '')
            .replaceAll('+', '.')) ??
        -1;
  }

  /// Returns an url as String when the app is not up-to-date otherwise empty string
  Future<String> checkUpdate(String version) async {
    try {
      var response = await Dio().get(updateUrl);
      if (response.data.length > 0) {
        var latest = response.data[0];
        String tagName = latest['tag_name'];

        if (versionToDouble(tagName) > versionToDouble(version)) {
          return latest['assets'][0]['browser_download_url'];
        }
      }
    } catch (e) {
      // ignored
    }
    return '';
  }

  /// Returns the message of the day
  Future<String> checkMotd() async {
    try {
      var response = await Dio().get(motdUrl);
      if (response.data.length > 0) {
        var jsonData = json.decode(response.data);
        String motd = jsonData['motd'];
        return motd;
      }
    } catch (e) {
      // ignored
    }
    return '';
  }

  /// Get list of distros from Repo
  Future<Map<String, String>> getDistroLinks() async {
    try {
      var response = await Dio().get(gitRepoLink);
      if (response.statusCode != null && response.statusCode! < 300) {
        var jsonData = jsonDecode(response.data);
        Map<String, String> distros = {};
        jsonData.forEach((key, value) {
          distros.addAll({key: value});
        });
        distroRootfsLinks = distros;
        return distros;
      }
    } catch (e) {
      // ignored
    }
    // Default list
    return distroRootfsLinks;
  }
}
