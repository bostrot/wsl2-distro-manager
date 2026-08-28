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

  /// In-distro `/etc/wsl.conf`, so a write can be read back.
  ///
  /// Null means the file does not exist, which is what `cat` reports on most
  /// freshly imported distros — the case the audit's CC-3 is about.
  String? wslConfContents;

  /// `wsl.exe` itself fails, e.g. the distro will not start. The config
  /// writer has to leave the file alone rather than replace it with the one
  /// key it was asked to set.
  bool simulateWslConfUnreachable = false;

  /// The redirection into `/etc/wsl.conf` fails — a read-only filesystem.
  bool simulateWslConfReadOnly = false;

  /// Every in-distro shell script [run] has been handed, in order. Counting
  /// them is how the settings dialog's debounce is measured.
  final List<String> runCommands = [];

  /// What `wsl --version` prints. Empty is the *inbox* build, which answers
  /// nothing useful — and is the default here so a test that does not opt in
  /// keeps taking the pre-WSL-2.5 code paths (`--manage` unavailable).
  String wslVersionOutput = '';

  /// Exit code of `wsl --version`. Non-zero is the documented inbox-build
  /// signature (`systemd.md:30`).
  int wslVersionExitCode = 0;

  /// What `wsl --status` prints.
  String wslStatusOutput = '';

  /// Every `ssh` invocation fails — the remote host is unreachable.
  bool sshFails = false;

  /// Every argument list [run] has been handed, in order. `lastRunArguments`
  /// only remembers one, which is not enough to assert that a *sequence*
  /// happened — "terminate, then move" — or that a step did **not**.
  final List<List<String>> runCalls = <List<String>>[];

  /// Every `wsl --manage` argument list this shell has been handed.
  final List<List<String>> manageCalls = <List<String>>[];

  /// Every `wsl --update` argument list.
  final List<List<String>> updateCalls = <List<String>>[];

  /// Every `wsl --install` argument list, so a `--from-file` install can be
  /// asserted on order and flags rather than on "something ran".
  final List<List<String>> installCalls = <List<String>>[];

  /// `wsl --install --from-file` fails with this message instead of
  /// succeeding.
  String? installFromFileFailure;

  /// In-distro `/etc/wsl-distribution.conf`, so a write can be read back.
  /// Null means the file does not exist, which is what every `--import`ed
  /// distro looks like (audit F-8).
  String? distributionConfContents;

  /// Absolute paths [readDistroFileList] should report as present.
  final Set<String> existingDistroFiles = <String>{};

  /// Paths `test -x` should answer yes for.
  final Set<String> executableDistroFiles = <String>{};

  /// Every `chmod` argument list the distro has been handed.
  final List<List<String>> chmodCalls = <List<String>>[];

  /// Arbitrary in-distro files this shell has been asked to write, by path.
  final Map<String, String> writtenDistroFiles = <String, String>{};

  /// `wsl --manage` fails with this message instead of succeeding.
  String? manageFailure;

  /// What `wsl --system … df -k …` prints.
  String dfOutput = '';

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
    runCalls.add(List<String>.from(arguments));

    String stdout = '';
    String stderr = '';
    int exitCode = 0;

    if (sshFails && executable == 'ssh') {
      return ProcessResult(
          0,
          255,
          stdoutEncoding == null ? <int>[] : '',
          stderrEncoding == null
              ? utf8.encode('ssh: connect to host: Connection refused')
              : 'ssh: connect to host: Connection refused');
    }

    // Every in-distro invocation now arrives as `--exec <shell> -c <script>`
    // (see lib/api/wsl_args.dart), so the command is the last argument
    // rather than a run of separate argv entries.
    if ((arguments.contains('sh') || arguments.contains('bash')) &&
        arguments.contains('-c')) {
      String cmd = arguments.last;
      runCommands.add(cmd);
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
      } else if (cmd == 'cat /etc/wsl.conf 2>/dev/null; exit 0') {
        // WSLApi.readWSLConf. `exit 0` means bash ran, so a non-zero status
        // here can only come from wsl.exe failing to reach the distro.
        if (simulateWslConfUnreachable) {
          stderr = 'There is no distribution with the supplied name.';
          exitCode = 1;
        } else {
          stdout = wslConfContents ?? execCmdAsRootResponse ?? '';
        }
      } else if (cmd.startsWith('cat ') &&
          cmd.endsWith(' 2>/dev/null; exit 0')) {
        // WSLApi.readDistroFile, of which readWSLConf and
        // readDistributionConf are the two schema-aware callers.
        final path = cmd.substring(
            'cat '.length, cmd.length - ' 2>/dev/null; exit 0'.length);
        if (simulateWslConfUnreachable) {
          stderr = 'There is no distribution with the supplied name.';
          exitCode = 1;
        } else if (path == '/etc/wsl-distribution.conf') {
          stdout = distributionConfContents ?? '';
        } else {
          // A file that is not there `cat`s as empty with status 0, which is
          // what the `2>/dev/null; exit 0` is for.
          stdout = writtenDistroFiles[path] ?? '';
        }
      } else if (cmd.startsWith('for f in ') && cmd.contains(r'[ -e $f ]')) {
        // WSLApi.readDistroFileList.
        if (simulateWslConfUnreachable) {
          exitCode = 1;
        } else {
          final paths =
              cmd.substring('for f in '.length, cmd.indexOf('; do')).split(' ');
          stdout = paths.where(existingDistroFiles.contains).join('\n');
        }
      } else if (cmd.startsWith("printf %s '") &&
          cmd.contains("' | base64 -d > ")) {
        // WSLApi.writeDistroFile, of which writeWSLConf is one caller.
        final marker = "' | base64 -d > ";
        final split = cmd.indexOf(marker);
        final path = cmd.substring(split + marker.length);
        if (simulateWslConfUnreachable || simulateWslConfReadOnly) {
          stderr = '$path: Read-only file system';
          exitCode = 1;
        } else {
          final payload = cmd.substring("printf %s '".length, split);
          final content = utf8.decode(base64.decode(payload));
          writtenDistroFiles[path] = content;
          if (path == '/etc/wsl.conf') {
            wslConfContents = content;
          } else if (path == '/etc/wsl-distribution.conf') {
            distributionConfContents = content;
          }
          existingDistroFiles.add(path);
        }
      }
    }

    // `--exec test -x <path>`: WSLApi.isExecutableInDistro. argv, not a
    // script, so it never reaches the `bash -c` branch above.
    if (arguments.contains('test') && arguments.contains('-x')) {
      final path = arguments.last;
      exitCode = executableDistroFiles.contains(path) ? 0 : 1;
    }

    if (arguments.contains('chmod')) {
      chmodCalls.add(List<String>.from(arguments));
      final path = arguments.last;
      if (arguments.contains('0755')) executableDistroFiles.add(path);
    }

    if (arguments.contains('--list')) {
      stdout = distros.join('\n');
    }

    if (arguments.length == 1 && arguments.first == '--version') {
      stdout = wslVersionOutput;
      exitCode = wslVersionExitCode;
      if (wslVersionExitCode != 0) {
        stderr = 'Invalid command line option: --version';
      }
    }

    if (arguments.length == 1 && arguments.first == '--status') {
      stdout = wslStatusOutput;
    }

    if (arguments.isNotEmpty && arguments.first == '--manage') {
      manageCalls.add(List<String>.from(arguments));
      if (manageFailure != null) {
        stderr = manageFailure!;
        exitCode = 1;
      } else if (arguments.contains('--move')) {
        // The native move relocates the disk without unregistering anything,
        // which is the whole point of preferring it (audit cli-flags CC-2).
        final target = arguments[arguments.indexOf('--move') + 1];
        File('$target/ext4.vhdx').createSync(recursive: true);
      }
    }

    if (arguments.isNotEmpty && arguments.first == '--update') {
      updateCalls.add(List<String>.from(arguments));
      stdout = 'The most recent version of WSL is already installed.';
    }

    if (arguments.contains('--system') && arguments.contains('df')) {
      stdout = dfOutput;
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
      installCalls.add(List<String>.from(arguments));
      if (arguments.contains('-d')) {
        String distro = arguments[arguments.indexOf('-d') + 1];
        distros.add(distro);
      }
      if (arguments.contains('--from-file')) {
        if (installFromFileFailure != null) {
          stderr = installFromFileFailure!;
          exitCode = 1;
        } else if (arguments.contains('--name')) {
          distros.add(arguments[arguments.indexOf('--name') + 1]);
        }
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

  /// Hands back a caller-supplied [Process] from [start] instead of the
  /// canned [MockProcess]. The streamed install path needs a child it can
  /// feed output to over time; everything else is happy with the default.
  Process Function()? processFactory;

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
  Future<Process> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    ProcessStartMode mode = ProcessStartMode.inheritStdio,
    bool runInShell = false,
  }) async {
    if (throwOnRun) throw Exception('shell error');
    lastCommand = [executable, ...arguments];
    allCommands.add([executable, ...arguments]);
    final factory = processFactory;
    if (factory != null) return factory();
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
    processFactory = null;
  }
}

/// A [Process] whose output and exit are driven by the test, one chunk at a
/// time.
///
/// [MockProcess] emits everything it has at once and (unless given a delay)
/// has already exited by the time anyone listens, which cannot express "still
/// running, still printing" — the shape the AI workspace install path's
/// silence timeout is built around.
class ControlledProcess implements Process {
  // Single-subscription, like a real process pipe. A broadcast controller
  // drops anything written before someone listens, and its cancel() never
  // completes under a widget test's fake clock — which strands any test that
  // drives an install through the UI.
  final StreamController<List<int>> _stdout = StreamController<List<int>>();
  final StreamController<List<int>> _stderr = StreamController<List<int>>();
  final Completer<int> _exited = Completer<int>();

  /// How many times [kill] was called, so a test can assert the child really
  /// was reaped rather than abandoned.
  int killCount = 0;
  ProcessSignal? lastKillSignal;

  /// What [exitCode] reports once the child has been killed. `-1` is the
  /// ordinary "died on a signal" answer, but `wsl.exe` is a Windows launcher
  /// around a Linux process and a terminated one can still hand back a
  /// perfectly clean `0` — which is why the service decides a killed install
  /// by its abandon reason and not by the exit code.
  int exitCodeOnKill = -1;

  /// WSL writes UTF-16LE, so every ASCII byte is followed by a null one —
  /// this mimics that on the way out, which is what the reader decodes.
  static List<int> _asWslBytes(String text) =>
      utf8.encode(text).expand((byte) => [byte, 0]).toList();

  void emit(String text) {
    if (!_stdout.isClosed) _stdout.add(_asWslBytes(text));
  }

  void emitError(String text) {
    if (!_stderr.isClosed) _stderr.add(_asWslBytes(text));
  }

  /// Ends the process normally with [code].
  void exit([int code = 0]) {
    _close();
    if (!_exited.isCompleted) _exited.complete(code);
  }

  void _close() {
    if (!_stdout.isClosed) _stdout.close();
    if (!_stderr.isClosed) _stderr.close();
  }

  @override
  Future<int> get exitCode => _exited.future;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killCount++;
    lastKillSignal = signal;
    _close();
    if (_exited.isCompleted) return false;
    _exited.complete(exitCodeOnKill);
    return true;
  }

  @override
  int get pid => 4242;

  @override
  Stream<List<int>> get stderr => _stderr.stream;

  @override
  IOSink get stdin => IOSink(StreamController<List<int>>().sink);

  @override
  Stream<List<int>> get stdout => _stdout.stream;
}
