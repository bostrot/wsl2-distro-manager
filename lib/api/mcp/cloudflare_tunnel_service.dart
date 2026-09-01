// Optional public exposure for the MCP server via a Cloudflare quick
// tunnel — outbound only, no account or port forwarding needed.
//
// Once on, the bearer token is the ONLY thing gating access, so the
// Settings UI has to spell that out. cloudflared is downloaded on first
// use and cached under the app data dir.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:localization/localization.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/components/notify.dart';

typedef TunnelProcessSpawner = Future<Process> Function(
    String executable, List<String> args);

typedef BinaryLocator = Future<String?> Function();

Future<Process> _defaultProcessSpawner(String executable, List<String> args) {
  return Process.start(executable, args);
}

class CloudflareTunnelService {
  /// Official release asset for this host. macOS ships as a tgz holding the
  /// binary; Windows and Linux are bare executables.
  static String get _downloadUrl {
    const base =
        'https://github.com/cloudflare/cloudflared/releases/latest/download/';
    if (Platform.isMacOS) return '${base}cloudflared-darwin-arm64.tgz';
    if (Platform.isLinux) return '${base}cloudflared-linux-amd64';
    return '${base}cloudflared-windows-amd64.exe';
  }
  static final RegExp _urlPattern =
      RegExp(r'https://[a-zA-Z0-9-]+\.trycloudflare\.com');
  static const Duration defaultUrlWaitTimeout = Duration(seconds: 25);

  // Static for the same reason as WslMcpService._server: one real tunnel,
  // however many wrappers.
  static Process? _process;
  static String? _publicUrl;
  static StreamSubscription<String>? _stdoutSub;
  static StreamSubscription<String>? _stderrSub;

  final TunnelProcessSpawner processSpawner;
  final BinaryLocator? binaryLocatorOverride;
  final Dio dio;
  final Duration urlWaitTimeout;

  CloudflareTunnelService({
    TunnelProcessSpawner? processSpawner,
    this.binaryLocatorOverride,
    Dio? dio,
    this.urlWaitTimeout = defaultUrlWaitTimeout,
  })  : processSpawner = processSpawner ?? _defaultProcessSpawner,
        dio = dio ?? Dio();

  bool get isRunning => _process != null;

  String? get publicUrl => _publicUrl;

  /// Cached copy, then PATH, then a fresh download.
  Future<String> _locateBinary() async {
    if (binaryLocatorOverride != null) {
      final located = await binaryLocatorOverride!();
      if (located != null) return located;
    }

    final cachedPath = _cachedBinaryPath();
    if (await File(cachedPath).exists() && await _binaryWorks(cachedPath)) {
      return cachedPath;
    }

    if (await _binaryWorks('cloudflared')) {
      return 'cloudflared';
    }

    Notify.message('cloudflare-tunnel-downloading-text'.i18n(),
        loading: true);
    if (_downloadUrl.endsWith('.tgz')) {
      // The macOS asset is an archive; unpack the one binary it contains.
      final archivePath = '$cachedPath.tgz';
      await dio.download(_downloadUrl, archivePath);
      final extract = await Process.run('tar', [
        '-xzf', archivePath,
        '-C', File(cachedPath).parent.path,
        'cloudflared',
      ]);
      try {
        File(archivePath).deleteSync();
      } catch (_) {}
      if (extract.exitCode != 0) {
        throw Exception(
            'Could not unpack cloudflared: ${extract.stderr}');
      }
    } else {
      await dio.download(_downloadUrl, cachedPath);
    }
    if (!Platform.isWindows) {
      await Process.run('chmod', ['+x', cachedPath]);
    }
    if (!await _binaryWorks(cachedPath)) {
      throw Exception(
          'Downloaded cloudflared but it did not run successfully.');
    }
    return cachedPath;
  }

  String _cachedBinaryPath() {
    final dir = getDataPath()..cd('bin');
    return dir.file(Platform.isWindows ? 'cloudflared.exe' : 'cloudflared');
  }

  Future<bool> _binaryWorks(String executable) async {
    try {
      final result = await Process.run(executable, ['--version'])
          .timeout(const Duration(seconds: 10));
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Starts a tunnel to `127.0.0.1:<localPort>` and returns the public URL.
  /// Throws if cloudflared cannot be run or reports no URL in time.
  Future<String> start(int localPort) async {
    if (isRunning && _publicUrl != null) return _publicUrl!;

    final executable = await _locateBinary();
    final process = await processSpawner(
      executable,
      ['tunnel', '--url', 'http://127.0.0.1:$localPort'],
    );
    _process = process;

    final urlCompleter = Completer<String>();
    void scanForUrl(String line) {
      if (urlCompleter.isCompleted) return;
      final match = _urlPattern.firstMatch(line);
      if (match != null) {
        urlCompleter.complete(match.group(0));
      }
    }

    _stdoutSub = process.stdout
        .cast<List<int>>()
        .transform(const SystemEncoding().decoder)
        .transform(const LineSplitter())
        .listen(scanForUrl);
    _stderrSub = process.stderr
        .cast<List<int>>()
        .transform(const SystemEncoding().decoder)
        .transform(const LineSplitter())
        .listen(scanForUrl);

    try {
      final url = await urlCompleter.future.timeout(urlWaitTimeout);
      _publicUrl = url;
      return url;
    } on TimeoutException {
      await stop();
      throw Exception(
          'Timed out waiting for cloudflared to report a tunnel URL.');
    }
  }

  Future<void> stop() async {
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;
    _process?.kill();
    _process = null;
    _publicUrl = null;
  }
}
