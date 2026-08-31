import 'dart:convert';
import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/services.dart' show rootBundle;
import 'package:wsl2distromanager/components/constants.dart';
import 'package:wsl2distromanager/components/helpers.dart';

class App {
  final Dio dio;

  App({Dio? dio}) : dio = dio ?? Dio();

  /// Debug builds read the repo's own bundled `images.json` instead of the
  /// CDN, so a catalogue change is testable in `flutter run` before the
  /// manual CDN push — the CDN copy, not the repo copy, is what release
  /// users get (see Working/cdn-upload.md), and with the CDN queried first a
  /// developer could never see their own edit. Static so a test can pick the
  /// path it is exercising; excluded under `flutter test` by default so the
  /// existing remote-path tests keep meaning what they say.
  static bool preferBundledCatalogue =
      kDebugMode && !Platform.environment.containsKey('FLUTTER_TEST');

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
      var response = await dio.get(updateUrl);
      if (response.data.length > 0) {
        var latest = response.data[0];
        String tagName = latest['tag_name'];
        String publishedAt = latest['published_at'];

        // Newer version and at least 2 days old
        if (versionToDouble(tagName) > versionToDouble(version) &&
            DateTime.now().difference(DateTime.parse(publishedAt)).inDays > 2) {
          return latest['html_url'];
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
      var response = await dio.get(motdUrl);
      if (response.data.length > 0) {
        var jsonData = json.decode(response.data);
        String motd = jsonData['motd'];
        // Check if same as last time
        if (prefs.getString('motd') == motd) {
          return '';
        }
        prefs.setString('motd', motd);
        return motd;
      }
    } catch (e) {
      // ignored
    }
    return '';
  }

  /// Get list of distros from Repo
  Future<Map<String, String>> getDistroLinks() async {
    // Debug: the bundled catalogue first, the CDN only as a fallback when
    // the asset is missing or unreadable.
    if (preferBundledCatalogue) {
      final local = await _getLocalDistroLinks();
      if (local.isNotEmpty) {
        distroRootfsLinks = local;
        return local;
      }
    }

    try {
      var response = await dio.get(gitRepoLink);
      if (response.statusCode != null && response.statusCode! < 300) {
        var jsonData = response.data;
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

    // Fallback: bundled images.json in app assets.
    final local = await _getLocalDistroLinks();
    if (local.isNotEmpty) {
      distroRootfsLinks = local;
      return local;
    }

    // Last resort: in-memory cache.
    return distroRootfsLinks;
  }

  Future<Map<String, String>> _getLocalDistroLinks() async {
    try {
      final raw = await rootBundle.loadString('images.json');
      final jsonData = json.decode(raw);
      if (jsonData is Map<String, dynamic>) {
        return jsonData.map((key, value) => MapEntry(key, value.toString()));
      }
    } catch (e) {
      // ignored
    }
    return {};
  }
}
