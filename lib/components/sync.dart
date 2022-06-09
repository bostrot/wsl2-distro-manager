import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:localization/localization.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_static/shelf_static.dart';
import 'package:wsl2distromanager/components/api.dart';
import 'package:wsl2distromanager/components/constants.dart';
import 'helpers.dart';
import 'package:http/http.dart' as http;
import 'package:async/async.dart';

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
    String? distroLocation = prefs.getString('Path_$distroName');
    if (distroLocation == null) {
      statusMsg('distronotfound-text'.i18n(), loading: false);
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
      statusMsg('syncipnotset-text'.i18n(), loading: false);
      return;
    }
    statusMsg('${'shuttingdownwsl-text'.i18n()}...', loading: true);
    // Shutdown WSL
    await WSLApi().shutdown();
    statusMsg('${'connectingtoip-text'.i18n()}: "$syncIP"...', loading: true);

    // Download file
    try {
      // Download file as a stream
      List<List<int>> chunks = [];
      int downloaded = 0;

      var httpClient = http.Client();
      // set buffer size to 10MB
      var request =
          http.Request('GET', Uri.parse('http://$syncIP:59132/ext4.vhdx'));
      var response = httpClient.send(request);

      response.asStream().listen((http.StreamedResponse r) async {
        final reader = ChunkedStreamReader(r.stream);
        int size = r.contentLength!;
        try {
          Uint8List buffer;
          do {
            buffer = await reader.readBytes(chunkSize);
            chunks.add(buffer);
            downloaded += buffer.length;
            statusMsg(
                '${'downloading-text'.i18n()} $distroName, '
                '(${downloaded ~/ 1024 ~/ 1024}MB'
                ' - ${(downloaded / size * 100).toStringAsFixed(0)}%)',
                loading: true);
          } while (buffer.length == chunkSize);
          // Write file
          File file = File('$distroLocation\\ext4.vhdx');
          final Uint8List bytes = Uint8List(r.contentLength!);
          int offset = 0;
          for (List<int> chunk in chunks) {
            bytes.setRange(offset, offset + chunk.length, chunk);
            offset += chunk.length;
          }
          await file.writeAsBytes(bytes);

          statusMsg('${'downloaded-text'.i18n()} $distroName');
        } catch (e) {
          statusMsg('${'errordownloading-text'.i18n()} $distroName',
              loading: false);
        } finally {
          reader.cancel();
        }
      });
    } catch (error) {
      statusMsg('${'errordownloading-text'.i18n()} $distroName',
          loading: false);
    }
  }
}
