import 'dart:io';

import 'package:dio/dio.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_static/shelf_static.dart';
import 'package:wsl2distromanager/components/api.dart';
import 'package:wsl2distromanager/components/list.dart';
import 'helpers.dart';

class Sync {
  late Function(String, {bool loading}) statusMsg;
  late String distroName;
  late String distroLocation;
  static late HttpServer server;

  Sync();

  /// Constructor
  /// @param {String} distroName
  /// @param {Function} statusMsg
  Sync.instance(this.distroName, this.statusMsg) {
    String? distroLocation = prefs.getString('Path_' + distroName);
    if (distroLocation == null) {
      statusMsg('Distro not found', loading: false);
      return;
    }
    this.distroLocation = distroLocation.replaceAll('/', '\\');
  }

  /// Check if distro has path in settings
  /// @param {String} distroName
  bool hasPath(String distroName) {
    String? distroLocation = prefs.getString('Path_' + distroName);
    if (distroLocation == null) {
      return false;
    }
    return true;
  }

  /// Start the server
  void startServer() async {
    // Get path for distro filesystem
    // Serve filesystem file
    var handler = createFileHandler(distroLocation + '\\ext4.vhdx',
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
      statusMsg('Sync IP not set. Please set it in the settings.',
          loading: false);
      return;
    }
    statusMsg('Shutting down WSL...', loading: true);
    // Shutdown WSL
    await WSLApi().shutdown();
    statusMsg('Connecting to IP: "$syncIP"...', loading: true);
    Dio().download(
        'http://$syncIP:59132/ext4.vhdx', distroLocation + '\\ext4.vhdx',
        onReceiveProgress: (received, total) {
      String rec = (received / 1024 / 1024).toStringAsFixed(2);
      String tot = (total / 1024 / 1024).toStringAsFixed(2);
      statusMsg('Downloading $distroName, $rec MB / $tot MB', loading: true);
      if (received == total) {
        statusMsg('Downloaded $distroName');
      }
    }).catchError((e) {
      statusMsg('Error downloading $distroName', loading: false);
    });
  }
}
