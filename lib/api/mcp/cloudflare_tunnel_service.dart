// Optional public exposure for the WSL MCP server via a Cloudflare "quick
// tunnel" (cloudflared connects outbound to Cloudflare's edge — no inbound
// firewall/port-forwarding changes, no Cloudflare account needed). This
// turns the local-only MCP endpoint into something reachable from anywhere,
// e.g. a cloud-hosted agent or another device — the bearer token in
// WslMcpService is the *only* thing gating access once this is on, so the
// Settings UI must make that trade-off explicit before enabling it.
//
// cloudflared itself is downloaded from Cloudflare's official GitHub
// releases the first time it's needed (or reused if already on PATH), and
// cached under the app's data directory afterward.

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
  static const String _downloadUrl =
      'https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe';
  static final RegExp _urlPattern =
      RegExp(r'https://[a-zA-Z0-9-]+\.trycloudflare\.com');
  static const Duration defaultUrlWaitTimeout = Duration(seconds: 25);

  // Static: same reasoning as WslMcpService's _server field — every
  // CloudflareTunnelService() instance must agree on the one real tunnel
  // process, not track its own.
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

  /// Finds a usable `cloudflared`, downloading it if necessary. Checks (in
  /// order): a previously-downloaded copy cached under the app data dir,
  /// then whatever's on PATH, then downloads a fresh copy.
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
    // getDataPath()..cd('bin') (in _cachedBinaryPath) already created the
    // containing directory — nothing more to prepare before downloading.
    await dio.download(_downloadUrl, cachedPath);
    if (!await _binaryWorks(cachedPath)) {
      throw Exception(
          'Downloaded cloudflared but it did not run successfully.');
    }
    return cachedPath;
  }

  String _cachedBinaryPath() {
    final dir = getDataPath()..cd('bin');
    return dir.file('cloudflared.exe');
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

  /// Starts a quick tunnel pointed at `http://127.0.0.1:<localPort>` and
  /// waits for cloudflared to report the public URL. Returns the URL, or
  /// throws if cloudflared can't be located/run or doesn't report a URL
  /// within [_urlWaitTimeout].
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
