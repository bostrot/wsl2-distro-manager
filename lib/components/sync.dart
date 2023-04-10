import 'dart:io';

import 'package:chunked_downloader/chunked_downloader.dart';
import 'package:localization/localization.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_static/shelf_static.dart';
import 'package:wsl2distromanager/api/wsl.dart';
import 'package:wsl2distromanager/components/notify.dart';
import 'helpers.dart';

class Sync {
  late String distroName;
  late String distroLocation;
  static late HttpServer server;

  Sync();

  /// Constructor
  /// @param {String} distroName
  /// @param {Function} Notify.message
  Sync.instance(this.distroName) {
    String? distroLocation = prefs.getString('Path_$distroName');
    if (distroLocation == null) {
      Notify.message('distronotfound-text'.i18n(), loading: false);
      return;
    }
    this.distroLocation = distroLocation.replaceAll('/', '\\');
  }

  /// Check if distro has path in settings
  /// @param {String} distroName
  bool hasPath(String distroName) {
    String? distroLocation = prefs.getString('Path_$distroName');
    if (distroLocation == null) {
      return false;
    }
    return true;
  }

  /// Start the server
  void startServer() async {
    // Get path for distro filesystem
    // Serve filesystem file
    var handler = createFileHandler('$distroLocation\\ext4.vhdx',
        contentType: "application/octet-stream");
    // Listen on network
    try {
      server = await io.serve(handler, '0.0.0.0', 59132);
    } catch (e) {
      // Do nothing
    }
  }

  /// Stop the server
  void stopServer() {
    server.close();
  }

  /// Download from sync IP
  void download() async {
    // Get path for distro filesystem
    String? syncIP = prefs.getString('SyncIP');
    if (syncIP == null) {
      Notify.message('syncipnotset-text'.i18n(), loading: false);
      return;
    }
    Notify.message('${'shuttingdownwsl-text'.i18n()}...', loading: true);

    // Shutdown WSL
    await WSLApi().shutdown();
    Notify.message('${'connectingtoip-text'.i18n()}: "$syncIP"...',
        loading: true);

    // Download using chunks
    var response = ChunkedDownloader(
        url: 'http://$syncIP:59132/ext4.vhdx',
        saveFilePath: '$distroLocation\\ext4.vhdx.tmp',
        onProgress: (progress, total, speed) {
          String rec = (progress / 1024 / 1024).toStringAsFixed(2);
          String tot = (total / 1024 / 1024).toStringAsFixed(2);
          Notify.message(
              '${'downloading-text'.i18n()} $distroName, $rec MB / $tot MB',
              loading: true);
          if (progress == total) {
            Notify.message('${'downloaded-text'.i18n()} $distroName');
            File oldFile = File('$distroLocation\\ext4.vhdx');
            oldFile.rename('$distroLocation\\ext4.vhdx.old');
            File file = File('$distroLocation\\ext4.vhdx.tmp');
            file.rename('$distroLocation\\ext4.vhdx');
          }
        },
        onError: (error) {
          Notify.message(
              '${'errordownloading-text'.i18n()} $distroName: $error',
              loading: false);
        });

    // Await download
    while (!response.done) {
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }
}
