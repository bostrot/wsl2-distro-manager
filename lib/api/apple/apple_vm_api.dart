import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:localization/localization.dart';
import 'package:path/path.dart' as p;
import 'package:wsl2distromanager/api/safe_paths.dart';
import 'package:wsl2distromanager/api/shell.dart';
import 'package:wsl2distromanager/api/vm/vm_backend.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/components/logging.dart';
import 'package:wsl2distromanager/components/notify.dart';

/// One VM as `vmctl list` reports it.
class AppleVmInfo {
  final String name;
  final String os; // 'linux' | 'macos'
  final String state; // 'running' | 'stopped'
  final int cpus;
  final int memoryBytes;
  final String diskPath;
  final int diskSizeBytes;
  final String user;
  final String? ip;

  const AppleVmInfo({
    required this.name,
    required this.os,
    required this.state,
    required this.cpus,
    required this.memoryBytes,
    required this.diskPath,
    required this.diskSizeBytes,
    required this.user,
    this.ip,
  });

  factory AppleVmInfo.fromJson(Map<String, dynamic> json) => AppleVmInfo(
        name: json['name'] as String? ?? '',
        os: json['os'] as String? ?? 'linux',
        state: json['state'] as String? ?? 'stopped',
        cpus: (json['cpus'] as num?)?.toInt() ?? 0,
        memoryBytes: (json['memoryBytes'] as num?)?.toInt() ?? 0,
        diskPath: json['diskPath'] as String? ?? '',
        diskSizeBytes: (json['diskSizeBytes'] as num?)?.toInt() ?? 0,
        user: json['user'] as String? ?? 'root',
        ip: json['ip'] as String?,
      );

  bool get running => state == 'running';
}

/// Raised when a `vmctl` invocation fails, carrying whatever the helper said.
class AppleVmException implements Exception {
  final String message;
  AppleVmException(this.message);

  @override
  String toString() => message;
}

/// Manages Linux and macOS virtual machines through Apple's
/// Virtualization.framework, by driving the bundled `vmctl` helper.
///
/// The helper owns the VM store (config, disk image, EFI store, per-VM SSH
/// key) and keeps each running VM alive in a detached daemon process; this
/// class stays a thin, mockable shell around its JSON protocol. Command
/// execution inside a guest goes over SSH with the key `vmctl create` seeds
/// via cloud-init, so it only works for guests provisioned that way (or where
/// the user set up SSH themselves) — mirroring how remote WSL depends on
/// key-based SSH.
class AppleVmApi extends VmBackend {
  final Shell shell;

  /// Overrides helper discovery; only tests set it.
  final String? helperPathOverride;

  /// Overrides the VM store directory; only tests set it.
  final String? storeDirOverride;

  AppleVmApi({
    Shell? shell,
    this.helperPathOverride,
    this.storeDirOverride,
    Duration? earlyExitProbeDelay,
  })  : shell = shell ?? ProcessShell(),
        earlyExitProbeDelay = earlyExitProbeDelay ?? _defaultEarlyExitProbeDelay;

  @override
  String get backendId => 'applevirt';

  @override
  String get instanceNoun => 'VM';

  @override
  String get templateExtension => 'img';

  @override
  VmFeatures get features => const VmFeatures(
        createVm: true,
        serialConsole: true,
        aiWorkspace: true,
        // Snippets are just saved scripts run inside an instance — works
        // over SSH exactly as it does over wsl.exe.
        quickActions: true,
      );

  /// The VM store: one directory per VM under the app's data path.
  String get storeDir =>
      storeDirOverride ?? (getDataPath()..cd('vms')).path;

  /// Where the `vmctl` helper lives, first match wins: an explicit
  /// `VMCTL_PATH`, the app bundle's Resources directory (release builds),
  /// the data dir, the stable install location `build_macos.sh` fills, the
  /// repo's own build output (debug runs from a checkout), then PATH.
  String helperPath() {
    if (helperPathOverride != null) return helperPathOverride!;
    final env = Platform.environment['VMCTL_PATH'];
    if (env != null && env.isNotEmpty && File(env).existsSync()) return env;

    final exeDir = p.dirname(Platform.resolvedExecutable);
    final home = Platform.environment['HOME'] ?? '';
    final pwd = Platform.environment['PWD'] ?? '';
    final candidates = <String>[
      p.normalize(p.join(exeDir, '..', 'Resources', 'vmctl')),
      p.join(getDataPath().path, 'bin', 'vmctl'),
      if (home.isNotEmpty)
        p.join(home, 'Library', 'Application Support', 'WSLManager', 'bin',
            'vmctl'),
      // `flutter run` from a checkout: the app inherits the tool's PWD.
      for (final root in {pwd, Directory.current.path})
        if (root.isNotEmpty) ...[
          p.join(root, 'macos', 'vmctl', '.build', 'release', 'vmctl'),
          p.join(root, 'macos', 'vmctl', '.build', 'debug', 'vmctl'),
        ],
    ];
    for (final candidate in candidates) {
      if (File(candidate).existsSync()) return candidate;
    }
    return 'vmctl';
  }

  List<String> _baseArgs() => ['--store', storeDir];

  Future<ProcessResult> _run(List<String> args) async {
    try {
      return await shell.run(
        helperPath(),
        [..._baseArgs(), ...args],
        runInShell: false,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
    } on ProcessException catch (e) {
      throw AppleVmException(
          'Could not run the vmctl helper (${helperPath()}): ${e.message}');
    }
  }

  /// Run vmctl and fail loudly with whatever it reported.
  Future<String> _runChecked(List<String> args) async {
    final result = await _run(args);
    final stdout = result.stdout.toString();
    if (result.exitCode != 0) {
      final stderr = result.stderr.toString().trim();
      throw AppleVmException(stderr.isNotEmpty
          ? stderr
          : 'vmctl ${args.join(' ')} failed with exit code ${result.exitCode}');
    }
    return stdout;
  }

  Future<List<AppleVmInfo>> listVms() async {
    final out = await _runChecked(['list', '--json']);
    try {
      final decoded = json.decode(out.trim().isEmpty ? '{}' : out);
      final vms = (decoded is Map ? decoded['vms'] : null) as List? ?? [];
      final parsed = vms
          .whereType<Map>()
          .map((vm) => AppleVmInfo.fromJson(Map<String, dynamic>.from(vm)))
          .toList();
      // Remember each running guest's IP so the row label can show it
      // without an extra helper round-trip per rebuild.
      _lastKnownIps.clear();
      for (final vm in parsed) {
        final ip = vm.ip;
        if (vm.running && ip != null && ip.isNotEmpty) {
          _lastKnownIps[vm.name] = ip;
        }
      }
      return parsed;
    } on FormatException catch (error, stack) {
      logError(error, stack, null);
      throw AppleVmException('vmctl returned unreadable output: $out');
    }
  }

  Future<AppleVmInfo?> vmInfo(String name) async {
    final vms = await listVms();
    for (final vm in vms) {
      if (vm.name == name) return vm;
    }
    return null;
  }

  @override
  Future<Instances> list(bool showDocker) async {
    final vms = await listVms();
    final instances = Instances(
      vms.map((vm) => vm.name).toList(),
      vms.where((vm) => vm.running).map((vm) => vm.name).toList(),
    );
    lastDistroList = instances;
    return instances;
  }

  @override
  Future<List<String>> listRunning() async {
    return (await list(false)).running;
  }

  /// How long after a successful `vmctl start` the VM is re-checked. A guest
  /// with nothing bootable powers itself off within a couple of seconds —
  /// EFI runs out of boot options — and without this check the app reported
  /// "started" over a VM window that had already closed itself. Injectable
  /// so tests don't sit through it.
  static const Duration _defaultEarlyExitProbeDelay = Duration(seconds: 4);
  final Duration earlyExitProbeDelay;

  @override
  Future<void> start(String distribution,
      {String startPath = '',
      String startUser = '',
      String startCmd = ''}) async {
    await _refuseIfDiskMounted(distribution);
    // Bring the VM up (idempotent for a VM that is already running) with its
    // display window, the Apple analogue of opening a distro's terminal.
    await _runChecked(['start', '--name', distribution, '--gui']);
    await _throwIfStoppedRightAway(distribution);
  }

  /// A disk attached in Finder and a running guest writing to it is data
  /// corruption; refuse the start with the remedy.
  Future<void> _refuseIfDiskMounted(String distribution) async {
    if (await diskIsAttached(distribution)) {
      throw AppleVmException('vmejectbeforestart-text'.i18n());
    }
  }

  /// Start without presenting a window — what the MCP tools want.
  Future<void> startHeadless(String distribution) async {
    await _refuseIfDiskMounted(distribution);
    await _runChecked(['start', '--name', distribution]);
    await _throwIfStoppedRightAway(distribution);
  }

  Future<void> _throwIfStoppedRightAway(String distribution) async {
    await Future.delayed(earlyExitProbeDelay);
    try {
      final vm = await vmInfo(distribution);
      if (vm == null || vm.running) return;
    } catch (_) {
      // The status probe failing is not evidence the VM died.
      return;
    }
    var message = 'vmstoppedimmediately-text'.i18n();
    final serialTail = _tailOfLog(distribution, 'serial.log');
    if (serialTail.isNotEmpty) {
      message = '$message\n$serialTail';
    }
    throw AppleVmException(message);
  }

  /// Last few hundred bytes of a per-VM run log, or '' when unavailable.
  String _tailOfLog(String distribution, String logName) {
    try {
      final log = File(p.join(storeDir, distribution, 'run', logName));
      if (!log.existsSync()) return '';
      final text = log.readAsStringSync();
      final tail = text.substring(text.length < 300 ? 0 : text.length - 300);
      return tail.trim();
    } catch (_) {
      return '';
    }
  }

  @override
  Future<String> stop(String distribution) =>
      _runChecked(['stop', '--name', distribution]);

  @override
  Future<String> shutdown() async {
    final running = await listRunning();
    for (final name in running) {
      await stop(name);
    }
    return '';
  }

  @override
  Future<String> remove(String distribution) async {
    final out = await _runChecked(['delete', '--name', distribution]);
    await clearDistroPrefs(distribution);
    return out;
  }

  @override
  Future<String> export(String distribution, String location,
      {String? format}) {
    return _runChecked(['export', '--name', distribution, '--output', location]);
  }

  @override
  Future<String> import(
      String distribution, String installLocation, String filename,
      {bool isVhd = false}) {
    return _runChecked(['import', '--name', distribution, '--input', filename]);
  }

  @override
  Future<String> execCmdAsRoot(String distribution, String cmd) async {
    final result = await execCommand(distribution, cmd);
    return result.stdout.toString();
  }

  /// Run [cmd] in the guest over SSH via `vmctl exec`.
  ///
  /// [cmd] is passed as a single argument, so it reaches the guest's shell
  /// verbatim — ssh flattens multi-token argv with spaces and lets the
  /// remote shell re-parse it, the same trap wsl.exe has (see
  /// lib/api/wsl_args.dart); one token has nothing to re-join.
  Future<ProcessResult> execCommand(
    String distribution,
    String cmd, {
    String user = 'root',
    String cwd = '',
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final full = cwd.isEmpty ? cmd : "cd '${cwd.replaceAll("'", "'\\''")}' && $cmd";
    try {
      return await shell
          .run(
            helperPath(),
            [
              ..._baseArgs(),
              'exec',
              '--name', distribution,
              '--user', user,
              '--',
              full,
            ],
            runInShell: false,
            stdoutEncoding: utf8,
            stderrEncoding: utf8,
          )
          .timeout(timeout);
    } on TimeoutException {
      return ProcessResult(
          0, 124, '', 'Command timed out after ${timeout.inSeconds}s');
    } on ProcessException catch (e) {
      throw AppleVmException(
          'Could not run the vmctl helper (${helperPath()}): ${e.message}');
    }
  }

  @override
  Future<Process> startShell(String distribution, {String? user}) {
    return shell.start(
      helperPath(),
      [
        ..._baseArgs(),
        'shell',
        '--name',
        distribution,
        if (user != null) ...['--user', user],
      ],
      runInShell: false,
    );
  }

  @override
  Future<void> runCommands(String instance, List<String> commands,
      {String? user}) async {
    // Run the snippet in the guest over SSH and show its output in a
    // Terminal window that stays open — the macOS analogue of WSLApi's
    // runCmds. The script travels base64-encoded so nothing in it has to be
    // escaped through the host shell, ssh's re-parse, or the guest shell.
    final script = commands.join('\n');
    final payload = base64.encode(utf8.encode(script));
    // One argument after `--`: the guest shell decodes and runs the snippet.
    final remote = 'printf %s $payload | base64 -d | sh';
    final runner = '#!/bin/bash\n'
        'echo "Running snippet in $instance…"\n'
        '"${helperPath()}" --store "$storeDir" exec '
        '--name "$instance" --user "${user ?? 'root'}" -- ${_shSingleQuote(remote)}\n'
        'echo\n'
        'read -n1 -r -p "Done. Press any key to close…" _\n';
    final scriptPath = p.join(storeDir, instance, 'run', 'snippet.command');
    File(scriptPath)
      ..createSync(recursive: true)
      ..writeAsStringSync(runner);
    await shell.run('chmod', ['+x', scriptPath], runInShell: false);
    await shell.start('open', [scriptPath],
        mode: ProcessStartMode.detached, runInShell: false);
  }

  static String _shSingleQuote(String value) =>
      "'${value.replaceAll("'", "'\\''")}'";

  @override
  Future<String> copy(String distribution, String newName) async {
    // A clone is an export/import round trip through a staging file, so the
    // source VM's disk is copied consistently by vmctl (which refuses while
    // the VM runs).
    final staging = p.join(storeDir, '.clone-$newName.img');
    try {
      await export(distribution, staging);
      return await import(newName, '', staging);
    } finally {
      final file = File(staging);
      if (file.existsSync()) file.deleteSync();
    }
  }

  String _diskPath(String distribution) =>
      p.join(storeDir, distribution, 'disk.img');

  /// Whether [distribution]'s disk image is currently attached via hdiutil
  /// (mounted in Finder).
  Future<bool> diskIsAttached(String distribution) async {
    try {
      final result = await shell.run('hdiutil', ['info'],
          runInShell: false, stdoutEncoding: utf8, stderrEncoding: utf8);
      return result.exitCode == 0 &&
          result.stdout.toString().contains(_diskPath(distribution));
    } catch (_) {
      return false;
    }
  }

  /// Browse the VM's disk itself: attach the raw image and open what mounts
  /// in Finder. macOS cannot mount ext4, so a pure-Linux disk falls back to
  /// the VM folder with an explanation — as does a running VM, whose disk
  /// must not be attached twice.
  @override
  void startExplorer(String distribution) async {
    void openStoreFolder() => shell.start(
        'open', [currentDistroPath(distribution)],
        mode: ProcessStartMode.detached);

    try {
      final vm = await vmInfo(distribution);
      if (vm != null && vm.running) {
        Notify.message('vmdiskinuse-text'.i18n(),
            severity: InfoBarSeverity.warning);
        openStoreFolder();
        return;
      }

      final result = await shell.run(
          'hdiutil',
          [
            'attach',
            '-imagekey',
            'diskimage-class=CRawDiskImage',
            _diskPath(distribution),
          ],
          runInShell: false,
          stdoutEncoding: utf8,
          stderrEncoding: utf8);
      final output = result.stdout.toString();
      if (result.exitCode == 0) {
        final volumes = RegExp(r'(/Volumes/.+)$', multiLine: true)
            .allMatches(output)
            .map((match) => match.group(1)!.trim())
            .toList();
        if (volumes.isNotEmpty) {
          for (final volume in volumes) {
            await shell.start('open', [volume],
                mode: ProcessStartMode.detached);
          }
          return;
        }
        // Attached, but macOS mounted nothing (ext4): detach again rather
        // than leaving a dangling device that blocks the next start.
        final device =
            RegExp(r'^(/dev/disk\d+)', multiLine: true).firstMatch(output);
        if (device != null) {
          await shell.run('hdiutil', ['detach', device.group(1)!],
              runInShell: false);
        }
      }
      Notify.message('vmdisknotmountable-text'.i18n(),
          severity: InfoBarSeverity.info);
      openStoreFolder();
    } catch (error, stack) {
      logDebug(error, stack, null);
      openStoreFolder();
    }
  }

  /// Guest IPs from the last `vmctl list`, running VMs only.
  final Map<String, String> _lastKnownIps = {};

  /// Real on-disk usage per VM ("1.24 GB"), filled by a background `du`.
  final Map<String, String> _diskUsageLabels = {};
  final Set<String> _diskUsageProbes = {};

  @override
  String instanceSizeLabel(String distribution) {
    try {
      final disk = File(p.join(storeDir, distribution, 'disk.img'));
      if (!disk.existsSync()) return '';
      final size = disk.lengthSync();
      if (size <= 0) return '';
      final allocated = '${(size / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
      // The image is sparse, so its logical length is the *allocated* size
      // every VM shows identically. Real usage comes from the file's blocks
      // (`du`), probed in the background; until the first probe answers the
      // honest thing to show is the allocation alone.
      _probeDiskUsage(distribution, disk.path);
      final used = _diskUsageLabels[distribution];
      return used == null ? allocated : '$used / $allocated';
    } catch (_) {
      return '';
    }
  }

  void _probeDiskUsage(String distribution, String diskPath) {
    if (_diskUsageProbes.contains(distribution)) return;
    _diskUsageProbes.add(distribution);
    shell
        .run('du', ['-k', diskPath], runInShell: false)
        .then((result) {
          if (result.exitCode != 0) return;
          final kb = int.tryParse(
              result.stdout.toString().trim().split(RegExp(r'\s+')).first);
          if (kb == null || kb < 0) return;
          _diskUsageLabels[distribution] =
              '${(kb / 1024 / 1024).toStringAsFixed(2)} GB';
        })
        .catchError((_) {})
        .whenComplete(() => _diskUsageProbes.remove(distribution));
  }

  @override
  String instanceMetaLabel(String distribution) {
    final size = instanceSizeLabel(distribution);
    final ip = _lastKnownIps[distribution];
    if (ip == null || ip.isEmpty) return size;
    return size.isEmpty ? ip : '$ip · $size';
  }

  @override
  Future<String?> getSize(String distribution) async {
    try {
      final vm = await vmInfo(distribution);
      if (vm == null || vm.diskSizeBytes <= 0) return null;
      final size = vm.diskSizeBytes / 1024 / 1024 / 1024;
      return '${'size-text'.i18n()}: ${size.toStringAsFixed(2)} GB';
    } catch (error, stack) {
      logDebug(error, stack, null);
      return null;
    }
  }

  @override
  String currentDistroPath(String distribution) =>
      (SafePath(storeDir)..cd(distribution)).path;

  @override
  Future<String> getDefaultUser(String distribution) async {
    try {
      final vm = await vmInfo(distribution);
      return vm?.user ?? 'root';
    } catch (_) {
      return 'root';
    }
  }

  /// Create a Linux VM. [isoPath] attaches an installer image for the first
  /// boot; [imagePath] seeds the disk from an existing raw image instead
  /// (e.g. a cloud image or a template). With neither the VM gets an empty
  /// disk. Sizes are in GB.
  Future<String> createLinuxVm(
    String name, {
    String? isoPath,
    String? imagePath,
    int diskSizeGb = 32,
    int cpus = 2,
    int memoryGb = 4,
    String user = 'user',
  }) {
    return _runChecked([
      'create',
      '--name', name,
      '--os', 'linux',
      '--disk-size', '$diskSizeGb',
      '--cpus', '$cpus',
      '--memory', '$memoryGb',
      '--user', user,
      if (isoPath != null && isoPath.isNotEmpty) ...['--iso', isoPath],
      if (imagePath != null && imagePath.isNotEmpty) ...['--image', imagePath],
    ]);
  }

  /// Create a macOS guest VM (Apple Silicon only). [restoreImagePath] is a
  /// local `.ipsw`; without it vmctl downloads the latest supported one.
  Future<String> createMacosVm(
    String name, {
    String? restoreImagePath,
    int diskSizeGb = 64,
    int cpus = 4,
    int memoryGb = 8,
  }) {
    return _runChecked([
      'create',
      '--name', name,
      '--os', 'macos',
      '--disk-size', '$diskSizeGb',
      '--cpus', '$cpus',
      '--memory', '$memoryGb',
      if (restoreImagePath != null && restoreImagePath.isNotEmpty)
        ...['--restore-image', restoreImagePath],
    ]);
  }

  /// Present a running VM's display window (opening it on first use — a
  /// headless-started VM has its graphics device either way).
  Future<void> showDisplay(String distribution) async {
    await _runChecked(['show', '--name', distribution]);
  }

  /// Open Terminal.app attached to the VM's serial console, starting the VM
  /// headless first when it is not running — a VM driven entirely from a
  /// terminal, no display window involved.
  ///
  /// Terminal is launched through a `.command` file rather than
  /// AppleScript: `open` needs no automation permission prompt.
  Future<void> openConsole(String distribution) async {
    final vm = await vmInfo(distribution);
    if (vm == null || !vm.running) {
      await startHeadless(distribution);
    }

    final script = '#!/bin/bash\n'
        'exec "${helperPath()}" --store "$storeDir" console '
        '--name "$distribution"\n';
    final scriptPath =
        p.join(storeDir, distribution, 'run', 'console.command');
    File(scriptPath)
      ..createSync(recursive: true)
      ..writeAsStringSync(script);
    await shell.run('chmod', ['+x', scriptPath], runInShell: false);
    await shell.start('open', [scriptPath],
        mode: ProcessStartMode.detached, runInShell: false);
  }

  /// The guest's current IP, or null while it has none (booting, no DHCP
  /// lease yet).
  Future<String?> guestIp(String name) async {
    try {
      final out = await _runChecked(['ip', '--name', name]);
      final decoded = json.decode(out);
      final ip = decoded is Map ? decoded['ip'] as String? : null;
      return (ip == null || ip.isEmpty) ? null : ip;
    } catch (_) {
      return null;
    }
  }
}
