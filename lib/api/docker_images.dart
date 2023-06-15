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
import 'package:wsl2distromanager/api/safe_paths.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/components/logging.dart';
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

class ImageManifestV1 {
  int schemaVersion = 1;
  String name = '';
  String tag = '';
  String architecture = '';
  List fsLayers = [];
  List history = [];
  List signatures = [];

  ImageManifestV1(
      {required this.schemaVersion,
      required this.name,
      required this.tag,
      required this.architecture,
      required this.fsLayers,
      required this.history,
      required this.signatures});

  factory ImageManifestV1.fromMap(Map<String, dynamic> map) => ImageManifestV1(
      schemaVersion: map["schemaVersion"],
      name: map["name"],
      tag: map["tag"],
      architecture: map["architecture"],
      fsLayers: List.from(map["fsLayers"]),
      history: List.from(map["history"]),
      signatures: List.from(map["signatures"]));
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
  static String registryUrl = 'https://registry-1.docker.io';
  static const String authUrl = 'https://auth.docker.io';
  static const String svcUrl = 'registry.docker.io';
  String? distroName;

  /// Get auth token
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
  Future<dynamic> _getManifest(
      String image, String token, String? digest) async {
    if (!image.contains("/")) {
      image = "library/$image";
    }
    Response<dynamic> response = await Dio().get(
      '$registryUrl/v2/$image/manifests/${digest ?? 'latest'}', // https://registry-1.docker.io/v2/nginx/manifests/latest
      // accept application/json
      options: Options(headers: {
        'Authorization': 'Bearer $token',
        // see https://github.com/opencontainers/image-spec/blob/main/media-types.md#oci-image-media-types
        'Accept': 'application/vnd.oci.descriptor.v1+json,'
            'application/vnd.oci.descriptor.v1+json,'
            'application/vnd.oci.layout.header.v1+json,'
            'application/vnd.oci.image.index.v1+json,'
            'application/vnd.oci.image.manifest.v1+json,'
            'application/vnd.oci.image.config.v1+json,'
            'application/vnd.oci.image.layer.v1.tar,'
            'application/vnd.oci.image.layer.v1.tar+gzip,'
            'application/vnd.oci.image.layer.v1.tar+zstd,'
            'application/vnd.oci.artifact.manifest.v1+json'
      }),
    );
    if (response.data == null) {
      throw Exception('No response data');
    }
    return response.data;
  }

  /// Download blob to file
  Future<bool> _downloadBlob(String image, String token, String digest,
      String file, ProgressCallback progressCallback) async {
    var downloader = ChunkedDownloader(
      url: '$registryUrl/v2/$image/blobs/$digest',
      saveFilePath: file,
      headers: {
        'Authorization': 'Bearer $token',
      },
      onProgress: (progress, total, speed) => progressCallback(progress, total),
      onDone: (file) {
        if (kDebugMode) {
          print('Download complete: $file');
        }
      },
      onError: (error) => throw Exception('Download failed $error'),
    );

    downloader.start();

    while (!downloader.done) {
      await Future.delayed(const Duration(milliseconds: 1000));
    }
    return true;
  }

  /// Download image
  Future<String> _download(
      String image, String path, TotalProgressCallback progressCallback,
      {String? tag}) async {
    // Get token
    final token = await _authenticate(image);

    var manifestData = await _getManifest(image, token, tag ?? 'latest');
    dynamic imageManifest;

    // TODO: When the manifest is in hand, the client must verify the signature to ensure the names and layers are valid.

    // Check if manifestData is a string
    if (manifestData is String) {
      // Get manifest
      manifestData = json.decode(manifestData);
    }

    // For logging
    Object? exception;
    StackTrace? stacktrace;

    // Multiple architectures per tag
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
      try {
        imageManifest =
            ImageManifest.fromMap(await _getManifest(image, token, digest));

        final config = imageManifest.config.digest;
        await _downloadBlob(image, token, config,
            SafePath(path).file('config.json'), (p0, p1) {});
      } catch (e, stackTrace) {
        if (kDebugMode) {
          print(e);
        }
        logError(e, stackTrace, null);
        return "false";
      }
    } else {
      // Single architecture
      try {
        imageManifest = ImageManifest.fromMap(manifestData);
      } catch (e, stack) {
        exception = e;
        stacktrace = stack;
      }
      try {
        imageManifest = ImageManifestV1.fromMap(manifestData);
      } catch (e, stack) {
        exception = e;
        stacktrace = stack;
      }
    }

    if (imageManifest is ImageManifest) {
      // Download layers
      final layers = imageManifest.layers;
      for (var i = 0; i < layers.length; i++) {
        final digest = layers[i].digest;
        if (kDebugMode) {
          print('Downloading $image layer ${i + 1} of ${layers.length}');
        }
        progressCallback(i, layers.length, 0, 100);
        await _downloadBlob(
            image, token, digest, SafePath(path).file('layer_$i.tar.gz'),
            (currentStep, totalStep) {
          progressCallback(i, layers.length, currentStep, totalStep);
        });
      }
    } else if (imageManifest is ImageManifestV1) {
      // Get ENV
      final config = imageManifest.history.first;
      // Parse
      final parsedConfig = json.decode(config["v1Compatibility"]);
      var parsedConfig2 = parsedConfig["config"];
      final env = parsedConfig2["Env"];
      final cmd = parsedConfig2["Cmd"];

      // Check if adduser or groupadd is in one of the commands
      List<String> userCmds = [];
      List<String> groupCmds = [];
      for (var item in imageManifest.history) {
        try {
          if (item["v1Compatibility"] == null) {
            continue;
          }
          item = json.decode(item["v1Compatibility"]);
          if (item["container_config"] == null) {
            continue;
          }
          item["container_config"]["Cmd"].forEach((element) {
            // User commands
            if (element.contains("adduser") || element.contains("useradd")) {
              userCmds.add(element);
            }
            // Group commands
            if (element.contains("groupadd") || element.contains("addgroup")) {
              groupCmds.add(element);
            }
            // Default user
            if (element.contains("USER")) {
              var user = element.split(' ')[1];
              if (user.contains(':')) {
                user = user.split(':')[0];
              }
              user = int.tryParse(user) ?? user;
              if (user is String) {
                // Add to shared preferences
                prefs.setString('StartUser_$distroName', user);
              } else {
                // User is a number
                // TODO: implement docker user is a number
                Notify.message('Not implemented yet: Docker USER is a number.');
              }
            }
          });
        } catch (e, stacktrace) {
          if (kDebugMode) {
            print(e);
          }
          logDebug(e, stacktrace, null);
        }
      }

      // Check if it has an entrypoint
      final entrypoint = parsedConfig2["Entrypoint"];
      var entrypointCmd = '';
      if (entrypoint != null && entrypoint is List) {
        entrypointCmd = entrypoint.map((e) => e).join(' ');
      }
      // Create export env command
      final exportEnv = env.map((e) => 'export $e;').join(' ');

      // Set image specific commands
      String name = filename(image, tag);
      if (cmd != null) {
        prefs.setString(
            'StartCmd_$name', '$exportEnv $entrypointCmd; ${cmd.join(' ')}');
      }
      prefs.setStringList('UserCmds_$name', userCmds);
      prefs.setStringList('GroupCmds_$name', groupCmds);

      // Download layers
      final layers = imageManifest.fsLayers;
      for (var i = 0; i < layers.length; i++) {
        final digest = layers[i]["blobSum"];

        if (kDebugMode) {
          print('Downloading $image layer ${i + 1} of ${layers.length}');
        }
        progressCallback(i, layers.length, 0, 100);
        await _downloadBlob(
            image, token, digest, SafePath(path).file('layer_$i.tar.gz'),
            (currentStep, totalStep) {
          progressCallback(i, layers.length, currentStep, totalStep);
        });
      }
    } else {
      Notify.message('Unknown manifest type');
      logError(exception ?? "No exception", stacktrace ?? StackTrace.current,
          imageManifest.toString());
      return "false";
    }

    return "true";
  }

  /// Putting layers into single tar file
  Future<bool> getRootfs(String name, String image,
      {String? tag,
      required TotalProgressCallback progress,
      bool skipDownload = false}) async {
    distroName = name;
    var distroPath = getDistroPath().path;

    // Add library to image name
    if (image.split('/').length == 1) {
      image = 'library/$image';
    }

    // Replace special chars
    final imageName = filename(image, tag);
    final tmpImagePath = (getTmpPath()..cd(imageName)).path;

    // Create distro folder

    var layers = 0;
    bool done = false;

    if (!skipDownload) {
      await _download(image, tmpImagePath,
          (current, total, currentStep, totalStep) {
        layers = total;
        if (kDebugMode) {
          print('${current + 1}/$total');
        }
        progress(current, total, currentStep, totalStep);
        if (current + 1 == total && currentStep == totalStep) {
          done = true;
        }
      }, tag: tag);
    }

    // Wait for download to finish
    while (!done && !skipDownload) {
      await Future.delayed(const Duration(milliseconds: 500));
    }

    Notify.message('Extracting layers ...');

    // Extract layers
    // Write the compressed tar file to disk.
    int retry = 0;

    String outArchive = SafePath(distroPath).file('$imageName.tar.gz');
    while (retry < 2) {
      try {
        Archive archive = Archive();

        // More than one layer
        if (layers != 1) {
          for (var i = 0; i < layers; i++) {
            // Read archives layers
            if (kDebugMode) {
              print('Extracting layer $i of $layers');
            }
            // progress(i, layers, -1, -1);
            Notify.message('Extracting layer $i of $layers');

            // In memory
            final tarfile = GZipDecoder().decodeBytes(
                File(SafePath(tmpImagePath).file('layer_$i.tar.gz'))
                    .readAsBytesSync());
            final subArchive = TarDecoder().decodeBytes(tarfile);

            // Add files to archive
            for (final file in subArchive) {
              archive.addFile(file);
              if (kDebugMode && !file.name.contains('/')) {
                if (kDebugMode) {
                  print('Adding root file ${file.name}');
                }
              }
            }
          }

          // Archive as tar then gzip to disk
          final tarfile = TarEncoder().encode(archive);
          final gzData = GZipEncoder().encode(tarfile);
          final fp = File(outArchive);

          Notify.message('writingtodisk-text'.i18n());
          fp.writeAsBytesSync(gzData!);
        } else if (layers == 1) {
          // Just copy the file
          File(SafePath(tmpImagePath).file('layer_0.tar.gz'))
              .copySync(outArchive);
        }

        retry = 2;
        break;
      } catch (e, stackTrace) {
        retry++;
        if (retry == 2) {
          logDebug(e, stackTrace, null);
        }
        await Future.delayed(const Duration(seconds: 1));
        if (kDebugMode) {
          print('Retrying $retry');
        }
      }
    }

    Notify.message('creatinginstance-text'.i18n());

    // Check if tar file is created
    if (!File(outArchive).existsSync()) {
      throw Exception('Tar file is not created');
    }
    // Wait for tar file to be created
    await Future.delayed(const Duration(seconds: 1));
    // Cleanup
    await Directory(tmpImagePath).delete(recursive: true);
    return true;
  }

  /// Check if registry has image
  Future<bool> _hasImageOnly(String image) async {
    try {
      await _authenticate(image);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Check if registry has image tag
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
  Future<bool> isDownloaded(String image, {String? tag = 'latest'}) async {
    return File(getDistroPath().file('${filename(image, tag)}.tar.gz'))
        .existsSync();
  }

  /// Formate image and tag to filename format
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
