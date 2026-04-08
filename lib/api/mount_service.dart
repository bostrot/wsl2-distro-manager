import 'dart:convert';
import 'dart:io';
import 'package:localization/localization.dart';
import 'package:path/path.dart' as p;
import 'package:wsl2distromanager/api/shell.dart';
import 'package:wsl2distromanager/api/wsl.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/components/logging.dart';

class PhysicalDisk {
  final String deviceId; // e.g. \\.\PHYSICALDRIVE1
  final String model;
  final String size;
  final int index;
  final String interfaceType;
  final String mediaType;

  PhysicalDisk({
    required this.deviceId,
    required this.model,
    required this.size,
    required this.index,
    required this.interfaceType,
    required this.mediaType,
  });

  @override
  String toString() => '$model ($size) - $deviceId';

  bool get isUsb => interfaceType.toUpperCase() == 'USB';
}

class MountService {
  final Shell shell;

  MountService({Shell? shell}) : shell = shell ?? ProcessShell();

  bool get _useRemoteWsl {
    final enabled = prefs.getBool('UseRemoteWSL') ?? false;
    final target = prefs.getString('RemoteWSLTarget')?.trim() ?? '';
    return enabled && target.isNotEmpty;
  }

  String get _remoteTarget {
    return prefs.getString('RemoteWSLTarget')?.trim() ?? '';
  }

  String get _sshControlPath {
    final tmpDir = Directory.systemTemp.path;
    return p.join(tmpDir, 'wsl2dm_ssh_mux.sock');
  }

  List<String> get _sshClientOptions {
    return <String>[
      '-o',
      'BatchMode=yes',
      '-o',
      'PasswordAuthentication=no',
      '-o',
      'KbdInteractiveAuthentication=no',
      '-o',
      'ControlMaster=auto',
      '-o',
      'ControlPersist=10m',
      '-o',
      'ControlPath=$_sshControlPath',
      '-o',
      'ServerAliveInterval=30',
      '-o',
      'ServerAliveCountMax=3',
    ];
  }

  List<String> _buildRemoteArgs(String executable, List<String> args) {
    return <String>[
      ..._sshClientOptions,
      '--',
      _remoteTarget,
      executable,
      ...args,
    ];
  }

  String _toUtf16LeBase64(String input) {
    final codeUnits = input.codeUnits;
    final bytes = <int>[];
    for (final unit in codeUnits) {
      bytes.add(unit & 0xFF);
      bytes.add((unit >> 8) & 0xFF);
    }
    return base64Encode(bytes);
  }

  Future<ProcessResult> _runHostPowershell(String script) async {
    if (_useRemoteWsl) {
      final encoded = _toUtf16LeBase64(script);
      return shell.run(
        'ssh',
        _buildRemoteArgs(
            'powershell', ['-NoProfile', '-EncodedCommand', encoded]),
        runInShell: false,
        stdoutEncoding: null,
        stderrEncoding: null,
      );
    }

    if (!Platform.isWindows) {
      throw Exception(
          'Physical disk operations require Windows host or remote WSL mode.');
    }

    return shell.run('powershell', ['-NoProfile', '-Command', script]);
  }

  String _safeProcessText(dynamic output) {
    if (output is List<int>) {
      return WSLApi().utf8Convert(output);
    }
    return output?.toString() ?? '';
  }

  Future<ProcessResult> _runWslHost(List<String> args) async {
    if (_useRemoteWsl) {
      return shell.run(
        'ssh',
        _buildRemoteArgs('wsl', args),
        runInShell: false,
      );
    }

    if (!Platform.isWindows) {
      throw Exception('WSL mount operations require Windows host or remote WSL mode.');
    }

    return shell.run('wsl', args);
  }

  Future<List<PhysicalDisk>> getPhysicalDisks() async {
    try {
      var result = await _runHostPowershell(
          'Get-CimInstance -ClassName Win32_DiskDrive | Select-Object DeviceID, Model, Size, Index, InterfaceType, MediaType | ConvertTo-Json');

      if (result.exitCode != 0) {
        throw Exception(
            'failedtolistdisks-text'.i18n([_safeProcessText(result.stderr)]));
      }

      String output = _safeProcessText(result.stdout).trim();
      if (output.isEmpty) return [];

      var json = jsonDecode(output);
      List<dynamic> list = (json is List) ? json : [json];

      return list.map((item) {
        double sizeGb = (item['Size'] ?? 0) / (1024 * 1024 * 1024);
        return PhysicalDisk(
          deviceId: item['DeviceID'],
          model: item['Model'],
          size: '${sizeGb.toStringAsFixed(2)} GB',
          index: item['Index'],
          interfaceType: item['InterfaceType'] ?? 'Unknown',
          mediaType: item['MediaType'] ?? 'Unknown',
        );
      }).toList();
    } catch (e, stack) {
      logError(e, stack, 'errorlistingdisks-text'.i18n());
      return [];
    }
  }

  Future<void> mountDisk(String diskPath,
      {String? partition,
      String? type,
      String? options,
      String? name,
      bool bare = false}) async {
    String args = '--mount $diskPath';

    if (bare) {
      args += ' --bare';
    } else {
      if (name != null && name.isNotEmpty) {
        args += ' --name "$name"';
      }
      if (partition != null && partition.isNotEmpty) {
        args += ' --partition $partition';
      }
      if (type != null && type.isNotEmpty) {
        args += ' --type $type';
      }
      if (options != null && options.isNotEmpty) {
        args += ' --options "$options"';
      }
    }

    if (_useRemoteWsl) {
      final wslArgs = ['--mount', diskPath];
      if (bare) {
        wslArgs.add('--bare');
      } else {
        if (name != null && name.isNotEmpty) {
          wslArgs.addAll(['--name', name]);
        }
        if (partition != null && partition.isNotEmpty) {
          wslArgs.addAll(['--partition', partition]);
        }
        if (type != null && type.isNotEmpty) {
          wslArgs.addAll(['--type', type]);
        }
        if (options != null && options.isNotEmpty) {
          wslArgs.addAll(['--options', options]);
        }
      }
      final result = await _runWslHost(wslArgs);
      if (result.exitCode != 0) {
        throw Exception(result.stderr.toString().trim());
      }
      return;
    }

    await _runAsAdmin('wsl', args);
  }

  String _getSafeName(String path) {
    String name = p.basenameWithoutExtension(path);
    // Sanitize name to be safe for WSL mount points
    name = name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
    if (name.isEmpty) name = 'disk';
    return name;
  }

  Future<void> mountVhd(String vhdPath,
      {String? partition,
      String? type,
      String? options,
      String? name,
      bool bare = false}) async {
    String windowsPath = vhdPath.replaceAll('/', '\\');
    String safeName =
        name != null && name.isNotEmpty ? name : _getSafeName(windowsPath);

    List<String> args = ['--mount', '"$windowsPath"', '--vhd'];

    if (bare) {
      args.add('--bare');
    } else {
      args.addAll(['--name', '"$safeName"']);
      if (partition != null && partition.isNotEmpty) {
        args.addAll(['--partition', partition]);
      }
      if (type != null && type.isNotEmpty) {
        // Only allow known filesystem types to prevent command injection
        const allowedTypes = ['ext4', 'xfs', 'btrfs', 'vfat', 'ntfs'];
        if (allowedTypes.contains(type)) {
          args.addAll(['--type', type]);
        } else {
          throw ArgumentError('invalidfilesystem-text'.i18n([type]));
        }
      }
      if (options != null && options.isNotEmpty) {
        args.addAll(['--options', options]);
      }
    }

    final result = await _runWslHost(args);
    if (result.exitCode != 0) {
      throw Exception(result.stderr.toString().trim());
    }
    await prefs.setString('mount_vhd_$safeName', windowsPath);
  }

  Future<void> unmount(String disk) async {
    String windowsPath = disk.replaceAll('/', '\\');
    // Strip \\?\ prefix if present (often returned by WSL error messages)
    if (windowsPath.startsWith('\\\\?\\')) {
      windowsPath = windowsPath.substring(4);
    }

    var result = await _runWslHost(['--unmount', windowsPath]);

    if (result.exitCode != 0) {
      throw Exception(result.stderr.toString().trim());
    }

    // If successful, clean up prefs just in case
    try {
      String name = _getSafeName(windowsPath);
      await prefs.remove('mount_vhd_$name');
    } catch (_) {}
  }

  Future<List<String>> getMountedDisks() async {
    // Get all prefs that start with 'mount_vhd_'
    List<String> mounted = [];
    for (String key in prefs.getKeys()) {
      if (key.startsWith('mount_vhd_')) {
        String? path = prefs.getString(key);
        if (path != null && path.isNotEmpty) {
          mounted.add(path);
        }
      }
    }
    return mounted;
  }

  Future<void> _runAsAdmin(String exe, String args) async {
    if (!Platform.isWindows) {
      throw Exception('Admin mount operations are only available on Windows hosts.');
    }

    final tempDir = Directory.systemTemp;
    final logFile = File('${tempDir.path}\\wsl_mount_log.txt');
    final exitCodeFile = File('${tempDir.path}\\wsl_mount_exit.txt');
    final batFile = File('${tempDir.path}\\wsl_mount_wrapper.bat');

    // Clean up previous runs
    if (await logFile.exists()) await logFile.delete();
    if (await exitCodeFile.exists()) await exitCodeFile.delete();
    if (await batFile.exists()) await batFile.delete();

    // Create a batch file to run the command and capture output/exit code
    // We use a batch file to avoid complex quoting issues with PowerShell/Start-Process
    // chcp 65001 ensures UTF-8 encoding for output
    final batContent = '''
@echo off
chcp 65001 > nul
$exe $args > "${logFile.path}" 2>&1
if %errorlevel% neq 0 (
  echo 1 > "${exitCodeFile.path}"
) else (
  echo 0 > "${exitCodeFile.path}"
)
''';
    await batFile.writeAsString(batContent);

    var result = await shell.run('powershell', [
      'Start-Process',
      '"${batFile.path}"',
      '-Verb',
      'RunAs',
      '-WindowStyle',
      'Hidden',
      '-Wait'
    ]);

    if (result.exitCode != 0) {
      throw Exception('failedtolaunchadmin-text'.i18n([result.stderr.toString()]));
    }

    // Check exit code file
    bool success = false;
    if (await exitCodeFile.exists()) {
      final content = (await exitCodeFile.readAsString()).trim();
      success = content == '0';
    }

    // Read log for output/error
    String output = '';
    if (await logFile.exists()) {
      try {
        var bytes = await logFile.readAsBytes();
        output = WSLApi().utf8Convert(bytes);
      } catch (e) {
        output = 'errorreadinglog-text'.i18n([e.toString()]);
      }
    }

    // Cleanup
    if (await batFile.exists()) await batFile.delete();
    if (await logFile.exists()) await logFile.delete();
    if (await exitCodeFile.exists()) await exitCodeFile.delete();

    if (!success) {
      // If output is empty but failed, provide a generic error
      if (output.isEmpty) {
        output = 'unknownmounterror-text'.i18n();
      }
      throw Exception(output);
    }
  }
}
