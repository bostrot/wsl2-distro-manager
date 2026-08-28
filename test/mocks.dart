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

  /// Whether the last [run] was routed through cmd.exe. In-distro WSL
  /// commands must not be — see lib/api/wsl_args.dart.
  bool lastRunInShell = false;
  String lastStartExecutable = '';
  List<String> lastRunArguments = [];
  String lastRunExecutable = '';
  String? execCmdAsRootResponse;
  String defaultUserHome = '/home/tester';

  bool simulateExportFailure = false;
  bool simulatePermissionDenied = false;
  bool simulateInvalidPath = false;
  String importFailureStdout = '';
  bool simulateSmallExport = false;
  bool simulateRemoveFailure = false;
  bool simulateCodeMissing = false;
  bool simulateCodiumMissing = false;
  // Bytes reported by the remote `Get-Item -LiteralPath ... .Length`
  // PowerShell probe used by WSLApi._remoteFileSize (getSize/move safety
  // checks). Defaults large enough to pass move()'s size-safety check.
  int remoteFileSizeBytes = 10 * 1024 * 1024;

  @override
  Future<ProcessResult> run(String executable, List<String> arguments,
      {String? workingDirectory,
      Map<String, String>? environment,
      bool includeParentEnvironment = true,
      bool runInShell = false,
      Encoding? stdoutEncoding = systemEncoding,
      Encoding? stderrEncoding = systemEncoding}) async {
    lastRunExecutable = executable;
    lastRunArguments = arguments;
    lastRunInShell = runInShell;

    String stdout = '';
    String stderr = '';
    int exitCode = 0;

    // Every in-distro invocation now arrives as `--exec <shell> -c <script>`
    // (see lib/api/wsl_args.dart), so the command is the last argument
    // rather than a run of separate argv entries.
    if ((arguments.contains('sh') || arguments.contains('bash')) &&
        arguments.contains('-c')) {
      String cmd = arguments.last;
      if (cmd == 'command -v code') {
        if (simulateCodeMissing) {
          exitCode = 1;
        }
      } else if (cmd == 'command -v codium') {
        if (simulateCodiumMissing) {
          exitCode = 1;
        }
      } else if (cmd == r'echo $HOME') {
        stdout = defaultUserHome;
      } else if (cmd == 'ls /testfile') {
        stdout = '/testfile\n';
      } else if (cmd == 'cat /etc/wsl.conf' && execCmdAsRootResponse != null) {
        stdout = execCmdAsRootResponse!;
      }
    }

    if (arguments.contains('--list')) {
      stdout = distros.join('\n');
    }

    if (arguments.contains('-Command') &&
        arguments.isNotEmpty &&
        arguments.last.contains('Get-Item')) {
      stdout = remoteFileSizeBytes.toString();
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
        stdout = importFailureStdout;
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

    // WSLApi.remove() runs `wsl --unregister` through Process.start (not
    // shell.run), so the same simulation the run() path offers has to exist
    // here too — otherwise remove() silently no-ops against the mock: the
    // distro stays in [distros] and simulateRemoveFailure never fires.
    if (arguments.contains('--unregister')) {
      final distro = arguments[arguments.indexOf('--unregister') + 1];
      if (simulateRemoveFailure) {
        return MockProcess(exitCode: 1, stderr: 'Unregister failed');
      }
      distros.remove(distro);
    }

    return MockProcess();
  }
}

class MockProcess implements Process {
  final int _exitCode;
  final List<List<int>> _stdoutChunks;
  final List<List<int>> _stderrChunks;
  final Completer<int> _exited = Completer<int>();
  Timer? _exitTimer;

  /// How many times [kill] was called. `ExecutionBroker.run()` must reap a
  /// timed-out child exactly once, so tests assert on this.
  int killCount = 0;

  /// The signal handed to the last [kill] call, if any.
  ProcessSignal? lastKillSignal;

  /// When set, the process stays alive for [delay] before exiting — the shape
  /// of a hung command. [kill] cuts it short.
  ///
  /// [stdoutChunks]/[stderrChunks] override the [stdout]/[stderr] strings and
  /// emit raw bytes in as many stream events as they contain, so tests can pin
  /// that a reader buffers the bytes before decoding rather than decoding each
  /// chunk on its own (a multi-byte sequence can straddle a chunk boundary).
  MockProcess({
    int exitCode = 0,
    String stdout = '',
    String stderr = '',
    List<List<int>>? stdoutChunks,
    List<List<int>>? stderrChunks,
    Duration? delay,
  })  : _exitCode = exitCode,
        _stdoutChunks = stdoutChunks ?? _asChunks(stdout),
        _stderrChunks = stderrChunks ?? _asChunks(stderr) {
    if (delay == null) {
      _exited.complete(exitCode);
    } else {
      _exitTimer = Timer(delay, () {
        if (!_exited.isCompleted) _exited.complete(_exitCode);
      });
    }
  }

  static List<List<int>> _asChunks(String text) =>
      text.isEmpty ? const <List<int>>[] : <List<int>>[utf8.encode(text)];

  @override
  Future<int> get exitCode => _exited.future;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killCount++;
    lastKillSignal = signal;
    _exitTimer?.cancel();
    if (_exited.isCompleted) return false;
    _exited.complete(-1);
    return true;
  }

  @override
  int get pid => 123;

  @override
  Stream<List<int>> get stderr => Stream.fromIterable(_stderrChunks);

  @override
  IOSink get stdin => IOSink(StreamController<List<int>>().sink);

  @override
  Stream<List<int>> get stdout => Stream.fromIterable(_stdoutChunks);
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

/// A minimal mock shell that returns configurable results.
///
/// Shared: the AI Workspace service tests and the screen tests both drive
/// an [ExecutionBroker] over this rather than each rolling their own.
class TestShell implements Shell {
  String stdoutData = '';
  String stderrData = '';
  int exitCode = 0;
  Duration? artificialDelay;
  bool throwOnRun = false;

  List<String> lastCommand = [];
  List<List<String>> allCommands = [];

  @override
  Future<ProcessResult> run(String executable, List<String> arguments,
      {String? workingDirectory,
      Map<String, String>? environment,
      bool includeParentEnvironment = true,
      bool runInShell = false,
      Encoding? stdoutEncoding,
      Encoding? stderrEncoding}) async {
    if (throwOnRun) throw Exception('shell error');
    lastCommand = [executable, ...arguments];
    allCommands.add([executable, ...arguments]);
    if (artificialDelay != null) await Future.delayed(artificialDelay!);
    return ProcessResult(
      -1, // pid placeholder
      exitCode,
      utf8.encode(stdoutData),
      utf8.encode(stderrData),
    );
  }

  @override
  Future<Process> start(String executable, List<String> arguments,
      {String? workingDirectory,
      Map<String, String>? environment,
      bool includeParentEnvironment = true,
      ProcessStartMode mode = ProcessStartMode.inheritStdio,
      bool runInShell = false}) async {
    if (throwOnRun) throw Exception('shell error');
    lastCommand = [executable, ...arguments];
    allCommands.add([executable, ...arguments]);
    // ExecutionBroker.run() goes through start() so it owns a killable handle;
    // startPersistent() uses the same entry point for keep-alive sessions.
    return MockProcess(
      exitCode: exitCode,
      stdout: stdoutData,
      stderr: stderrData,
      delay: artificialDelay,
    );
  }

  void reset() {
    stdoutData = '';
    stderrData = '';
    exitCode = 0;
    lastCommand.clear();
    allCommands.clear();
    artificialDelay = null;
    throwOnRun = false;
  }
}
