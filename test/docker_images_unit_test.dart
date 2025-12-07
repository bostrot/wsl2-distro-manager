import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chunked_downloader/chunked_downloader.dart' as cd;
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wsl2distromanager/api/archive.dart';
import 'package:wsl2distromanager/api/docker_images.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/components/notify.dart';

class MockAdapter implements HttpClientAdapter {
  final Map<String, ResponseBody> responses;

  MockAdapter(this.responses);

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    // Check for partial match for regex urls
    for (var key in responses.keys) {
      if (options.path.contains(key)) {
        return responses[key]!;
      }
    }
    return ResponseBody.fromString('Not Found', 404);
  }

  @override
  void close({bool force = false}) {}
}

class MockChunkedDownloader extends cd.ChunkedDownloader {
  MockChunkedDownloader({
    required String url,
    required String saveFilePath,
    Map<String, String>? headers,
    int chunkSize = 1024 * 1024,
    cd.ProgressCallback? onProgress,
    cd.OnDoneCallback? onDone,
    cd.OnErrorCallback? onError,
  }) : super(
            url: url,
            saveFilePath: saveFilePath,
            headers: headers,
            chunkSize: chunkSize,
            onProgress: onProgress,
            onDone: onDone,
            onError: onError);

  @override
  Future<cd.ChunkedDownloader> start() async {
    // Simulate download
    onProgress?.call(100, 100, 1.0);
    // Create dummy file
    File(saveFilePath).createSync(recursive: true);
    done = true;
    onDone?.call(File(saveFilePath));
    return this;
  }
}

class MockArchiveService implements ArchiveService {
  @override
  Future<void> extract(String archivePath, String destinationPath) async {
    // Create dummy extracted files if needed
  }

  @override
  Future<void> merge(List<String> archivePaths, String destinationPath) async {
    File(destinationPath).createSync(recursive: true);
  }

  @override
  Future<void> compress(String filePath, String destinationPath) async {
    File(destinationPath).createSync(recursive: true);
  }
}

const customRegistry = 'http://192.168.3.156:5000';

void main() {
  late DockerImage dockerImage;
  late Dio dio;
  late MockAdapter adapter;
  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    
    // Mock Notify
    Notify();
    Notify.message = (String msg, {
      Duration? duration,
      dynamic severity = "",
      bool loading = false,
      bool useWidget = false,
      bool leadingIcon = true,
      dynamic widget,
    }) {};

    dio = Dio();
    adapter = MockAdapter({});
    dio.httpClientAdapter = adapter;

    tempDir = await Directory.systemTemp.createTemp('docker_test');
    prefs.setString('DistroPath', tempDir.path);

    dockerImage = DockerImage(
      dio: dio,
      registryUrl: customRegistry,
      chunkedDownloaderFactory: ({required url, required saveFilePath, headers, chunkSize, onProgress, onDone, onError}) =>
          MockChunkedDownloader(
              url: url,
              saveFilePath: saveFilePath,
              headers: headers,
              chunkSize: chunkSize ?? 1024 * 1024,
              onProgress: onProgress,
              onDone: onDone,
              onError: onError),
      archiveService: MockArchiveService(),
    );
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test('hasImage returns true if image exists', () async {
    adapter.responses['token'] = ResponseBody.fromString(
        jsonEncode({'token': 'dummy_token'}), 200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});

    // Mock manifest on custom registry
    adapter.responses['$customRegistry/v2/library/alpine/manifests/latest'] = ResponseBody.fromString(
        jsonEncode({}), 200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});

    expect(await dockerImage.hasImage('library/alpine'), true);
  });

  test('hasImage returns false if token fails', () async {
    adapter.responses['token'] = ResponseBody.fromString(
        jsonEncode({'error': 'failed'}), 401,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});

    expect(await dockerImage.hasImage('library/alpine'), false);
  });

  test('getRootfs downloads and extracts image', () async {
    // Mock token
    adapter.responses['token'] = ResponseBody.fromString(
        jsonEncode({'token': 'dummy_token'}), 200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});

    // Mock manifest (single arch)
    final manifest = {
      "schemaVersion": 2,
      "mediaType": "application/vnd.docker.distribution.manifest.v2+json",
      "config": {
        "mediaType": "application/vnd.docker.container.image.v1+json",
        "size": 100,
        "digest": "sha256:config_digest"
      },
      "layers": [
        {
          "mediaType": "application/vnd.docker.image.rootfs.diff.tar.gzip",
          "size": 100,
          "digest": "sha256:layer_digest"
        }
      ]
    };
    adapter.responses['$customRegistry/v2/library/alpine/manifests/latest'] = ResponseBody.fromString(
        jsonEncode(manifest), 200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});

    await dockerImage.getRootfs('test', 'library/alpine', tag: 'latest', progress: (c, t, cs, ts) {});

    // Verify output file exists
    final outFile = '${tempDir.path}/distros/library_alpine_latest.tar.gz';
    expect(File(outFile).existsSync(), true);
  });

  test('DockerImage uses custom registry', () async {
    // This test is now redundant as all tests use the custom registry, 
    // but we can keep it to be explicit about the configuration capability.
    final customDockerImage = DockerImage(
      dio: dio,
      registryUrl: customRegistry,
      chunkedDownloaderFactory: ({required url, required saveFilePath, headers, chunkSize, onProgress, onDone, onError}) =>
          MockChunkedDownloader(
              url: url,
              saveFilePath: saveFilePath,
              headers: headers,
              chunkSize: chunkSize ?? 1024 * 1024,
              onProgress: onProgress,
              onDone: onDone,
              onError: onError),
      archiveService: MockArchiveService(),
    );

    // Mock token for custom registry (if needed, or just standard auth url if not changed)
    adapter.responses['token'] = ResponseBody.fromString(
        jsonEncode({'token': 'dummy_token'}), 200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});

    // Mock manifest on custom registry
    final manifest = {
      "schemaVersion": 2,
      "mediaType": "application/vnd.docker.distribution.manifest.v2+json",
      "config": {
        "mediaType": "application/vnd.docker.container.image.v1+json",
        "size": 100,
        "digest": "sha256:config_digest"
      },
      "layers": []
    };
    
    // The URL should be constructed using the custom registry
    adapter.responses['$customRegistry/v2/library/alpine/manifests/latest'] = ResponseBody.fromString(
        jsonEncode(manifest), 200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});

    expect(await customDockerImage.hasImage('library/alpine'), true);
  });
}
