/// API to download docker images from DockerHub and extract them
/// into a rootfs.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:chunked_downloader/chunked_downloader.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:localization/localization.dart';
import 'package:wsl2distromanager/components/constants.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/components/notify.dart';

class Manifests {
  List<Manifest> manifests = [];
  String mediaType = '';
  int schemaVersion = 2;

  Manifests(
      {required this.manifests,
      required this.mediaType,
      required this.schemaVersion});

  factory Manifests.fromMap(Map<String, dynamic> map) => Manifests(
      manifests:
          List<Manifest>.from(map["manifests"].map((x) => Manifest.fromMap(x))),
      mediaType: map["mediaType"],
      schemaVersion: map["schemaVersion"]);
}

class Manifest {
  String digest = '';
  String mediaType = '';
  PlatformManifest? platform;
  int size = 0;

  Manifest(
      {required this.digest,
      required this.mediaType,
      this.platform,
      required this.size});

  Manifest.empty();

  Manifest.fromMap(Map<String, dynamic> map) {
    digest = map["digest"];
    mediaType = map["mediaType"];
    if (map["platform"] != null) {
      platform = PlatformManifest.fromMap(map["platform"]);
    }
    size = map["size"];
  }
}

class ImageManifest {
  Config config = Config.empty();
  List<Manifest> layers = [];
  String mediaType = '';
  int schemaVersion = 2;

  ImageManifest(
      {required this.config,
      required this.layers,
      required this.mediaType,
      required this.schemaVersion});

  factory ImageManifest.fromMap(Map<String, dynamic> map) => ImageManifest(
      config: Config.fromMap(map["config"]),
      layers:
          List<Manifest>.from(map["layers"].map((x) => Manifest.fromMap(x))),
      mediaType: map["mediaType"],
      schemaVersion: map["schemaVersion"]);
}

class Config {
  String mediaType = '';
  String digest = '';
  int size = 0;

  Config({required this.mediaType, required this.digest, required this.size});
  Config.empty();

  factory Config.fromMap(Map<String, dynamic> map) => Config(
      mediaType: map["mediaType"], digest: map["digest"], size: map["size"]);
}

class PlatformManifest {
  String architecture = '';
  String os = '';

  PlatformManifest({required this.architecture, required this.os});

  factory PlatformManifest.fromMap(Map<String, dynamic> map) =>
      PlatformManifest(architecture: map["architecture"], os: map["os"]);
}

typedef ProgressCallback = void Function(int count, int total);
typedef TotalProgressCallback = void Function(
    int count, int total, int countStep, int totalStep);

class DockerImage {
  static const String registryUrl = 'https://registry-1.docker.io';
  static const String authUrl = 'https://auth.docker.io';
  static const String svcUrl = 'registry.docker.io';

  /// Get auth token
  /// @param {String} image
  /// @result {String} token
  /// @throws {Exception} if token is not found
  Future<String> _authenticate(String image) async {
    Response<dynamic> response = await Dio().get(
      '$authUrl/token?service=$svcUrl&scope=repository:$image:pull',
    );
    if (response.data == null) {
      throw Exception('No response data');
    }
    final token = response.data['token'];
    if (token == null) {
      throw Exception('No token found');
    }
    return token as String;
  }

  /// Get manifest
  /// @param {String} image
  /// @param {String} token
  /// @param {String} digest
  /// @result {String} manifest
  /// @throws {Exception} if manifest is not found
  Future<dynamic> _getManifest(
      String image, String token, String? digest) async {
    Response<dynamic> response = await Dio().get(
      '$registryUrl/v2/$image/manifests/${digest ?? 'latest'}',
      // accept application/json
      options: Options(headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.docker.distribution.manifest.list.v2+json, '
            'application/vnd.docker.distribution.manifest.v2+json, '
            'application/vnd.docker.distribution.manifest.v1+json',
      }),
    );
    if (response.data == null) {
      throw Exception('No response data');
    }
    return response.data;
  }

  /// Download blob to file
  /// @param {String} image
  /// @param {String} token
  /// @param {String} digest
  /// @param {String} path
  /// @result {bool} success
  Future<bool> _downloadBlob(String image, String token, String digest,
      String file, ProgressCallback progressCallback) async {
    ChunkedDownloader(
      url: '$registryUrl/v2/$image/blobs/$digest',
      fileName: file,
      savedDir: '',
      onProgress: (int count, int total, double speed) {
        Notify.message('${'downloading-text'.i18n()} '
            '${(count / total * 100).toStringAsFixed(0)}% '
            '(${(speed / ~1024 / ~1024).toStringAsFixed(2)} MB/s)');
      },
      onDone: ((file) {
        Notify.message('${'downloaded-text'.i18n()} $filename');
      }),
      onError: (error) {
        Notify.message('${'errordownloading-text'.i18n()} $filename');
        throw Exception('Download failed');
      },
    ).start();
    return true;
  }

  /// Download image
  /// @param {String} image The image name
  /// @param {String} path The path to extract the image to
  /// @param {Function} progressCallback The progress callback
  /// @result {String} msg
  Future<String> _download(
      String image, String path, TotalProgressCallback progressCallback,
      {String? tag}) async {
    // Get token
    final token = await _authenticate(image);

    final manifestData = await _getManifest(image, token, tag ?? 'latest');
    ImageManifest imageManifest;

    if (manifestData['manifests'] != null) {
      // Get manifest
      final data = Manifests.fromMap(manifestData);

      // Find amd64 digest
      var manifest = data.manifests.firstWhere(
          (element) => element.platform?.architecture == 'amd64',
          orElse: () => Manifest.empty());
      var digest = manifest.digest;

      // Download amd64 blob
      if (kDebugMode) {
        print('Downloading $image amd64 blob');
      }
      imageManifest =
          ImageManifest.fromMap(await _getManifest(image, token, digest));
      final config = imageManifest.config.digest;
      await _downloadBlob(
          image, token, config, '$path/config.json', (p0, p1) {});
    } else {
      imageManifest = ImageManifest.fromMap(manifestData);
    }

    // Download layers
    final layers = imageManifest.layers;
    for (var i = 0; i < layers.length; i++) {
      final digest = layers[i].digest;
      if (kDebugMode) {
        print('Downloading $image layer ${i + 1} of ${layers.length}');
      }
      progressCallback(i, layers.length, 0, 100);
      await _downloadBlob(image, token, digest, '$path/layer_$i.tar.gz',
          (currentStep, totalStep) {
        progressCallback(i, layers.length, currentStep, totalStep);
      });
    }

    return "true";
  }

  /// Putting layers into single tar file
  /// @param {String} image
  /// @param {String} path
  /// @result {bool} success
  /// @throws {Exception} if tar file is not created
  Future<bool> getRootfs(String image,
      {String? tag, required TotalProgressCallback progress}) async {
    final distroPath = prefs.getString("SaveLocation") ?? defaultPath;

    // Replace special chars
    final filename =
        '${image.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}_${tag ?? 'latest'}';
    final path = '$distroPath/tmp/$filename';
    var layers = 0;
    await _download(image, path, (current, total, currentStep, totalStep) {
      layers = total;
      if (kDebugMode) {
        print('${current + 1}/$total');
      }
      progress(current, total, currentStep, totalStep);
    }, tag: tag);

    // Put layers into single tar file
    final outputStream =
        OutputFileStream('$distroPath/distros/$filename.tar.gz');
    for (var i = 0; i < layers; i++) {
      final inputStream = InputFileStream('$path/layer_$i.tar.gz');
      outputStream.writeInputStream(inputStream);
      inputStream.close();
    }
    outputStream.close();
    // Check if tar file is created
    if (!File('$distroPath/distros/$filename.tar.gz').existsSync()) {
      throw Exception('Tar file is not created');
    }
    // Cleanup
    Directory(path).deleteSync(recursive: true);
    return true;
  }

  /// Check if registry has image
  /// @param {String} image
  /// @result {bool} hasImage
  Future<bool> _hasImageOnly(String image) async {
    try {
      await _authenticate(image);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Check if registry has image tag
  /// @param {String} image
  /// @param {String} tag
  /// @result {bool} hasImageTag
  Future<bool> hasImage(String image, {String? tag}) async {
    bool hasImage = await _hasImageOnly(image);
    if (tag == null) {
      return hasImage;
    }
    try {
      if (!hasImage) {
        return false;
      }
      await _getManifest(image, await _authenticate(image), tag);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Check if image is already downloaded
  /// @param {String} image
  /// @result {bool} isDownloaded
  Future<bool> isDownloaded(String image, {String tag = 'latest'}) async {
    final distroPath = prefs.getString("SaveLocation") ?? defaultPath;
    // Replace special chars
    return File('$distroPath/distros/${filename(image, tag)}.tar.gz')
        .existsSync();
  }

  /// Formate image and tag to filename format
  /// @param {String} image
  /// @param {String} tag
  /// @result {String} filename
  /// @throws {Exception} if image or is not valid
  String filename(String image, String? tag) {
    if (image.isEmpty) {
      throw Exception('Image is not valid');
    }
    final filename = image.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    if (tag == null) {
      return filename;
    }
    final tagFilename = tag.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    return '${filename}_$tagFilename';
  }
}
