import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chunked_downloader/chunked_downloader.dart' as cd;
import 'package:dio/dio.dart';
import 'package:http/http.dart';
import 'package:async/async.dart';
import 'package:wsl2distromanager/api/docker_images.dart';
import 'package:wsl2distromanager/api/shell.dart';
import 'package:wsl2distromanager/components/helpers.dart';

class MockHttpClientAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    if (options.path.contains('releases')) {
      return ResponseBody.fromString(
          jsonEncode([
            {
              'tag_name': 'v2.0.0',
              'published_at': DateTime.now()
                  .subtract(const Duration(days: 3))
                  .toIso8601String(),
              'html_url': 'https://github.com/example/release.msix'
            }
          ]),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType]
          });
    }
    if (options.path.contains('motd')) {
      return ResponseBody.fromString(jsonEncode({'motd': 'Hello Test'}), 200,
          headers: {
            Headers.contentTypeHeader: [Headers.textPlainContentType]
          });
    }
    if (options.path.contains('images.json')) {
      return ResponseBody.fromString(
          jsonEncode({'Debian': 'http://example.com/debian.tar.gz'}), 200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType]
          });
    }
    return ResponseBody.fromString('', 404);
  }

  @override
  void close({bool force = false}) {}
}

class MockShell implements Shell {
  final List<String> distros = [];
  List<String> lastStartArguments = [];
  String lastStartExecutable = '';
  String? execCmdAsRootResponse;

  bool simulateExportFailure = false;
  bool simulatePermissionDenied = false;
  bool simulateInvalidPath = false;
  bool simulateSmallExport = false;
  bool simulateRemoveFailure = false;

  @override
  Future<ProcessResult> run(String executable, List<String> arguments,
      {String? workingDirectory,
      Map<String, String>? environment,
      bool includeParentEnvironment = true,
      bool runInShell = false,
      Encoding? stdoutEncoding = systemEncoding,
      Encoding? stderrEncoding = systemEncoding}) async {
    String stdout = '';
    String stderr = '';
    int exitCode = 0;

    if (arguments.contains('--list')) {
      stdout = distros.join('\n');
    }

    if (arguments.contains('--unregister')) {
      if (simulateRemoveFailure) {
        stderr = 'Unregister failed';
        exitCode = 1;
      } else {
        distros.remove(arguments[1]);
      }
    }

    if (arguments.contains('--export')) {
      String location = arguments[2];
      if (simulatePermissionDenied) {
        stderr = 'Permission denied';
        exitCode = 1;
      } else if (simulateExportFailure) {
        stderr = 'Export failed';
        exitCode = 2;
      } else {
        File(location).createSync(recursive: true);
        // Create a file large enough to pass the >10MB safety check
        final f = File(location).openSync(mode: FileMode.write);
        if (simulateSmallExport) {
          f.truncateSync(1024); // 1KB
        } else {
          f.truncateSync(10 * 1024 * 1024 + 100); // 10MB + 100 bytes
        }
        f.closeSync();
      }
    }

    if (arguments.contains('--import')) {
      String distro = arguments[1];
      String installLocation = arguments[2];
      if (simulateInvalidPath) {
        stderr = 'Invalid installation path: $installLocation';
        exitCode = 3;
      } else if (simulatePermissionDenied) {
        stderr = 'Permission denied';
        exitCode = 1;
      } else {
        if (!distros.contains(distro)) {
          distros.add(distro);
        }
        File('$installLocation/ext4.vhdx').createSync(recursive: true);
      }
    }

    if (arguments.contains('--unregister')) {
      String distro = arguments[1];
      distros.remove(distro);
    }

    if (arguments.contains('--install')) {
      if (arguments.contains('-d')) {
        String distro = arguments[arguments.indexOf('-d') + 1];
        distros.add(distro);
      }
    }

    if (arguments.contains('ls') && arguments.contains('/testfile')) {
      stdout = '/testfile\n';
    }

    if (arguments.contains('cat') && arguments.contains('/etc/wsl.conf')) {
      if (execCmdAsRootResponse != null) {
        stdout = execCmdAsRootResponse!;
      }
    }

    dynamic stdoutData = stdout;
    if (stdoutEncoding == null) {
      stdoutData = utf8.encode(stdout);
    }

    dynamic stderrData = stderr;
    if (stderrEncoding == null) {
      stderrData = utf8.encode(stderr);
    }

    return ProcessResult(0, exitCode, stdoutData, stderrData);
  }

  @override
  Future<Process> start(String executable, List<String> arguments,
      {String? workingDirectory,
      Map<String, String>? environment,
      bool includeParentEnvironment = true,
      bool runInShell = false,
      ProcessStartMode mode = ProcessStartMode.normal}) async {
    lastStartExecutable = executable;
    lastStartArguments = arguments;
    // Return a dummy process
    return MockProcess();
  }
}

class MockProcess implements Process {
  @override
  Future<int> get exitCode => Future.value(0);

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    return true;
  }

  @override
  int get pid => 123;

  @override
  Stream<List<int>> get stderr => Stream.empty();

  @override
  IOSink get stdin => IOSink(StreamController<List<int>>().sink);

  @override
  Stream<List<int>> get stdout => Stream.empty();
}

class MockDockerImage extends DockerImage {
  @override
  Future<bool> isDownloaded(String image, {String? tag}) async {
    return false;
  }

  @override
  Future<bool> hasImage(String image, {String? tag}) async {
    return true;
  }

  @override
  Future<bool> getRootfs(String name, String image,
      {String? tag,
      bool skipDownload = false,
      required Function(int, int, int, int) progress}) async {
    progress(100, 100, 100, 100);
    String filename = this.filename(image, tag);
    String path = getDistroPath().file('$filename.tar.gz');
    File(path).createSync(recursive: true);
    File(path).writeAsBytesSync(List.filled(3 * 1024 * 1024, 0));
    return true;
  }
}

class MockChunkedDownloader implements cd.ChunkedDownloader {
  @override
  String url = '';
  @override
  String saveFilePath = '';
  @override
  int chunkSize = 0;
  @override
  cd.ProgressCallback? onProgress;
  @override
  cd.OnDoneCallback? onDone;
  @override
  cd.OnErrorCallback? onError;
  @override
  void Function()? onCancel;
  @override
  void Function()? onPause;
  @override
  void Function()? onResume;
  @override
  StreamSubscription<StreamedResponse>? stream;
  @override
  ChunkedStreamReader<int>? reader;
  @override
  Map<String, String>? headers;
  @override
  double speed = 0;
  @override
  bool paused = false;
  @override
  bool done = false;

  @override
  Future<cd.ChunkedDownloader> start() async {
    if (onDone != null) {
      onDone!(File(saveFilePath));
    }
    return this;
  }

  @override
  void pause() {}

  @override
  void resume() {}

  @override
  void stop() {}
}

class MockHttpServer extends Stream<HttpRequest> implements HttpServer {
  bool closed = false;

  @override
  Future close({bool force = false}) async {
    closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    return super.noSuchMethod(invocation);
  }

  @override
  StreamSubscription<HttpRequest> listen(
      void Function(HttpRequest event)? onData,
      {Function? onError,
      void Function()? onDone,
      bool? cancelOnError}) {
    return const Stream<HttpRequest>.empty().listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }
}
