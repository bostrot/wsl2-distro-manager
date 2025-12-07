import 'dart:io';

import 'package:chunked_downloader/chunked_downloader.dart';
import 'package:localization/localization.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_static/shelf_static.dart';
import 'package:wsl2distromanager/api/wsl.dart';
import 'package:wsl2distromanager/components/notify.dart';
import 'helpers.dart';

typedef ChunkedDownloaderFactory = ChunkedDownloader Function({
  required String url,
  required String saveFilePath,
  Function(int, int, double)? onProgress,
  Function(dynamic)? onError,
});

typedef ServerFactory = Future<HttpServer> Function(
    Handler handler, Object address, int port);

ChunkedDownloader _defaultChunkedDownloaderFactory({
  required String url,
  required String saveFilePath,
  Function(int, int, double)? onProgress,
  Function(dynamic)? onError,
}) {
  return ChunkedDownloader(
    url: url,
    saveFilePath: saveFilePath,
    onProgress: onProgress,
    onError: onError,
  );
}

Future<HttpServer> _defaultServerFactory(
    Handler handler, Object address, int port) {
  return io.serve(handler, address, port);
}

class Sync {
  late String distroName;
  late String distroLocation;
  static late HttpServer server;

  final WSLApi wslApi;
  final ChunkedDownloaderFactory chunkedDownloaderFactory;
  final ServerFactory serverFactory;

  Sync({
    WSLApi? wslApi,
    ChunkedDownloaderFactory? chunkedDownloaderFactory,
    ServerFactory? serverFactory,
  })  : wslApi = wslApi ?? WSLApi(),
        chunkedDownloaderFactory =
            chunkedDownloaderFactory ?? _defaultChunkedDownloaderFactory,
        serverFactory = serverFactory ?? _defaultServerFactory;

  /// Constructor
  Sync.instance(
    this.distroName, {
    WSLApi? wslApi,
    ChunkedDownloaderFactory? chunkedDownloaderFactory,
    ServerFactory? serverFactory,
  })  : wslApi = wslApi ?? WSLApi(),
        chunkedDownloaderFactory =
            chunkedDownloaderFactory ?? _defaultChunkedDownloaderFactory,
        serverFactory = serverFactory ?? _defaultServerFactory;

  /// Check if distro has path in settings
  bool hasPath(String distroName) {
    return prefs.getString('Path_$distroName') != null ? true : false;
  }

  /// Start the server
  Future<void> startServer() async {
    var handler = createFileHandler(
        getInstancePath(distroName).file('ext4.vhdx'),
        contentType: "application/octet-stream");
    try {
      server = await serverFactory(handler, '0.0.0.0', 59132);
    } catch (e) {
      // Do nothing
    }
  }

  /// Stop the server
  void stopServer() {
    server.close();
  }

  /// Download from sync IP
  Future<void> download() async {
    String? syncIP = prefs.getString('SyncIP');
    if (syncIP == null) {
      Notify.message('syncipnotset-text'.i18n(), loading: false);
      return;
    }
    Notify.message('${'shuttingdownwsl-text'.i18n()}...', loading: true);

    final vhdxPath = getInstancePath(distroName).file('ext4.vhdx');
    final vhdxPathTmp = getInstancePath(distroName).file('ext4.vhdx.tmp');
    final vhdxPathOld = getInstancePath(distroName).file('ext4.vhdx.old');

    await wslApi.shutdown();
    Notify.message('${'connectingtoip-text'.i18n()}: "$syncIP"...',
        loading: true);

    var downloader = chunkedDownloaderFactory(
        url: 'http://$syncIP:59132/ext4.vhdx',
        saveFilePath: vhdxPathTmp,
        onProgress: (progress, total, speed) {
          String rec = (progress / 1024 / 1024).toStringAsFixed(2);
          String tot = (total / 1024 / 1024).toStringAsFixed(2);
          Notify.message(
              '${'downloading-text'.i18n()} $distroName, $rec MB / $tot MB',
              loading: true);
        },
        onError: (error) {
          Notify.message(
              '${'errordownloading-text'.i18n()} $distroName: $error',
              loading: false);
        });

    var response = await downloader.start();

    while (!response.done) {
      await Future.delayed(const Duration(milliseconds: 500));
    }

    Notify.message('${'downloaded-text'.i18n()} $distroName');
    File oldFile = File(vhdxPath);
    if (await oldFile.exists()) {
      await oldFile.rename(vhdxPathOld);
    }
    File file = File(vhdxPathTmp);
    if (await file.exists()) {
      await file.rename(vhdxPath);
    }
  }
}
