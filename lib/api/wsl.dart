import 'dart:async';
import 'dart:io';
import 'dart:convert' show Encoding, Utf8Decoder, utf8;
import 'package:chunked_downloader/chunked_downloader.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:localization/localization.dart';

import 'package:path/path.dart' as p;
import 'package:flutter/services.dart' show rootBundle;
import 'package:wsl2distromanager/api/app.dart';
import 'package:wsl2distromanager/api/safe_paths.dart';
import 'package:wsl2distromanager/api/shell.dart';
import 'package:wsl2distromanager/components/constants.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/components/logging.dart';
import 'package:wsl2distromanager/components/notify.dart';

/// Used to store the instances of WSL in a list.
class Instances {
  List<String> running = [];
  List<String> all = [];
  Instances(this.all, this.running);
}

bool inited = false;

/// This class is used to interact with WSL. It contains all the functions
/// needed to interact with WSL based on Process.run and Process.start.
/// Most functions will return the UTF8 converted stdout of the process.
class WSLApi {
  final Shell shell;
  static const Duration _remoteListTimeout = Duration(seconds: 12);
  static final RegExp _remoteTargetPattern =
      RegExp(r'^(?:(?!-)[A-Za-z0-9._-]+@)?(?!-)[A-Za-z0-9._:-]+$');

  WSLApi({Shell? shell}) : shell = shell ?? ProcessShell() {
    if (!inited) {
      inited = true;
      App().getDistroLinks();
    }
  }

  bool get _useRemoteWsl {
    final enabled = prefs.getBool('UseRemoteWSL') ?? false;
    final target = prefs.getString('RemoteWSLTarget')?.trim() ?? '';
    return enabled && _isValidRemoteTarget(target);
  }

  bool get useRemoteWsl => _useRemoteWsl;

  String get remoteTargetLabel {
    final target = prefs.getString('RemoteWSLTarget')?.trim() ?? '';
    return target;
  }

  bool _isValidRemoteTarget(String target) {
    final trimmed = target.trim();
    return trimmed.isNotEmpty && _remoteTargetPattern.hasMatch(trimmed);
  }

  String get _remoteTarget {
    final target = prefs.getString('RemoteWSLTarget')?.trim() ?? '';
    if (!_isValidRemoteTarget(target)) {
      throw StateError('Invalid remote WSL target configured.');
    }
    return target;
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

  String get _remoteRootPath => 'C:\\wsl2dm';

  String _remoteSafeComponent(String value) {
    return replaceSpecialChars(value).replaceAll(RegExp(r'_+'), '_');
  }

  String _remoteDefaultInstallPath(String distribution) {
    return '$_remoteRootPath\\instances\\${_remoteSafeComponent(distribution)}';
  }

  String remoteInstallPath(String distribution) {
    return _remoteDefaultInstallPath(distribution);
  }

  String _remoteInstallPathFor(String distribution) {
    final saved = prefs.getString('Path_$distribution')?.trim() ?? '';
    if (saved.isNotEmpty) {
      return saved;
    }
    return _remoteDefaultInstallPath(distribution);
  }

  String _remoteStagingPath(String distribution, String localPath) {
    return '$_remoteRootPath\\staging\\${_remoteSafeComponent(distribution)}\\${_remoteSafeComponent(p.basename(localPath))}';
  }

  String _remoteParentPath(String remotePath) {
    final lastSeparator = remotePath.lastIndexOf('\\');
    if (lastSeparator <= 0) {
      return remotePath;
    }
    return remotePath.substring(0, lastSeparator);
  }

  String _escapePowerShellSingleQuoted(String input) {
    return input.replaceAll("'", "''");
  }

  Future<String> _readRemoteWslConfigText() async {
    final script =
        r"$p = Join-Path $env:USERPROFILE '.wslconfig'; if (Test-Path -LiteralPath $p) { Get-Content -LiteralPath $p -Raw }";
    final result = await shell.run(
      'ssh',
      _buildRemoteArgs('powershell', ['-NoProfile', '-Command', script]),
      runInShell: false,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );

    if (result.exitCode != 0) {
      return '';
    }

    return result.stdout?.toString() ?? '';
  }

  Future<void> _writeRemoteWslConfigText(String content) async {
    final escapedContent = _escapePowerShellSingleQuoted(content);
    final script =
        "\$p = Join-Path \$env:USERPROFILE '.wslconfig'; [IO.File]::WriteAllText(\$p, '$escapedContent', [Text.UTF8Encoding]::new(\$false))";

    final result = await shell.run(
      'ssh',
      _buildRemoteArgs('powershell', ['-NoProfile', '-Command', script]),
      runInShell: false,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );

    if (result.exitCode != 0) {
      throw Exception(
          'Failed to write remote .wslconfig on $remoteTargetLabel: ${result.stderr}');
    }
  }

  Future<void> _ensureRemoteDirectory(String path) async {
    await shell.run(
      'ssh',
      _buildRemoteArgs('cmd', [
        '/c',
        'if',
        'not',
        'exist',
        '"$path"',
        'mkdir',
        '"$path"',
      ]),
      runInShell: false,
      stdoutEncoding: systemEncoding,
      stderrEncoding: systemEncoding,
    );
  }

  Future<String> _stageLocalFileToRemote(String localPath, String remotePath) async {
    await _ensureRemoteDirectory(_remoteParentPath(remotePath));

    await shell.run(
      'scp',
      [
        ..._sshClientOptions,
        localPath,
        '$_remoteTarget:$remotePath',
      ],
      runInShell: false,
      stdoutEncoding: systemEncoding,
      stderrEncoding: systemEncoding,
    );

    return remotePath;
  }

  List<String> _buildRemoteArgs(
    String executable,
    List<String> args, {
    bool allocateTty = false,
  }) {
    final remoteArgs = <String>[..._sshClientOptions];
    if (allocateTty) {
      remoteArgs.add('-tt');
    }
    remoteArgs.add('--');
    remoteArgs.add(_remoteTarget);
    remoteArgs.add(executable);
    remoteArgs.addAll(args);
    return remoteArgs;
  }

  Future<ProcessResult> _runWsl(
    List<String> args, {
    bool runInShell = false,
    Encoding? stdoutEncoding = systemEncoding,
    Encoding? stderrEncoding = systemEncoding,
  }) {
    if (!_useRemoteWsl) {
      return shell.run(
        'wsl',
        args,
        runInShell: runInShell,
        stdoutEncoding: stdoutEncoding,
        stderrEncoding: stderrEncoding,
      );
    }

    return shell.run(
      'ssh',
      _buildRemoteArgs('wsl', args),
      runInShell: false,
      stdoutEncoding: stdoutEncoding,
      stderrEncoding: stderrEncoding,
    );
  }

  Future<Process> _startWsl(
    List<String> args, {
    bool runInShell = false,
    ProcessStartMode mode = ProcessStartMode.normal,
    bool allocateTty = false,
  }) {
    if (!_useRemoteWsl) {
      return shell.start(
        'wsl',
        args,
        runInShell: runInShell,
        mode: mode,
      );
    }

    return shell.start(
      'ssh',
      _buildRemoteArgs('wsl', args, allocateTty: allocateTty),
      runInShell: false,
      mode: mode,
    );
  }

  /// Get distro size of [distroName] a string with a GB suffix.
  /// Returns null if size is 0.
  /// e.g. "2.00 GB"
  Future<String?> getSize(String distroName) async {
    if (_useRemoteWsl) {
      final vhdxPath = '${_remoteInstallPathFor(distroName)}\\ext4.vhdx';
      final escapedPath = _escapePowerShellSingleQuoted(vhdxPath);
      final script =
          "if (Test-Path -LiteralPath '$escapedPath') { (Get-Item -LiteralPath '$escapedPath').Length }";

      final result = await shell.run(
        'ssh',
        _buildRemoteArgs('powershell', ['-NoProfile', '-Command', script]),
        runInShell: false,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );

      if (result.exitCode != 0) {
        return null;
      }

      final raw = (result.stdout?.toString() ?? '').trim();
      final byteSize = int.tryParse(raw);
      if (byteSize == null || byteSize <= 0) {
        return null;
      }

      final size = byteSize / 1024 / 1024 / 1024;
      return '${'size-text'.i18n()}: ${size.toStringAsFixed(2)} GB';
    }

    String ext4Path = getInstancePath(distroName).file('ext4.vhdx');
    // Get size of distro
    try {
      File file = File(ext4Path);
      int byteSize = file.lengthSync();
      if (byteSize == 0) {
        return null;
      }
      double size = byteSize / 1024 / 1024 / 1024; // Convert to GB
      return '${'size-text'.i18n()}: ${size.toStringAsFixed(2)} GB';
    } catch (error, stack) {
      logDebug(error, stack, null);
      return null;
    }
  }

  /// Create directory
  void mkRootDir({String? path}) {
    SafePath(path ?? getDefaultStorageRootPath());
  }

  /// Install WSL
  void installWSL() async {
    if (_useRemoteWsl) {
      final result = await _runWsl(['--install']);
      if (result.exitCode == 0) {
        Notify.message('Triggered WSL install on remote host $remoteTargetLabel.');
      } else {
        Notify.message(
            'Failed to trigger remote WSL install on $remoteTargetLabel: ${result.stderr}');
      }
      return;
    }

    shell.start(
        'powershell',
        [
          'Start-Process cmd -ArgumentList "/c wsl --install" -Verb RunAs',
        ],
        mode: ProcessStartMode.detached,
        runInShell: true);
  }

  /// Start a WSL distro by name
  void start(String distribution,
      {String startPath = '',
      String startUser = '',
      String startCmd = ''}) async {
    List<String> wslArgs = [];
    wslArgs.addAll(['-d', distribution]);
    if (startPath != '') {
      wslArgs.addAll(['--cd', startPath]);
    }
    if (startUser != '') {
      wslArgs.addAll(['--user', startUser]);
    }
    if (startCmd != '') {
      for (String cmd in startCmd.split(' ')) {
        wslArgs.add(cmd);
      }
      // Run shell to keep open
      wslArgs.add(';/bin/sh');
    }

    List<String> args = _useRemoteWsl
        ? _buildRemoteArgs('wsl', wslArgs, allocateTty: true)
        : ['wsl', ...wslArgs];

    String executable = 'start';
    String? terminal = prefs.getString('Terminal');
    if (terminal != null && terminal.isNotEmpty) {
      executable = terminal;
    }
    // If using Windows Terminal, open in new tab of existing window
    if (executable.toLowerCase().endsWith('wt.exe') ||
        executable.toLowerCase() == 'wt') {
      // -w 0 targets the existing window (or creates one if none exists)
      // nt (new-tab) creates a new tab
      // We insert these at the beginning of the arguments list
      args.insertAll(0, ['-w', '0', 'nt']);
    }

    if (Platform.isLinux) {
      await _startLinuxTerminal(_useRemoteWsl ? ['ssh', ...args] : args);
      if (kDebugMode) {
        print("Done starting $distribution");
      }
      return;
    }

    await shell.start(executable, args,
        mode: ProcessStartMode.detached, runInShell: true);
    if (kDebugMode) {
      print("Done starting $distribution");
    }
  }

  /// Stop a WSL distro by name
  Future<String> stop(String distribution) async {
    ProcessResult results = await _runWsl(['--terminate', distribution]);
    return results.stdout;
  }

  /// Open bashrc with notepad from WSL
  Future<String> openBashrc(String distribution) async {
    String editor = prefs.getString('Editor') ?? 'notepad.exe';
    List<String> argsRc = _useRemoteWsl
        ? _buildRemoteArgs('wsl', ['-d', distribution, editor, '.bashrc'])
        : ['wsl', '-d', distribution, editor, '.bashrc'];

    if (Platform.isLinux) {
      await _startLinuxTerminal(_useRemoteWsl ? ['ssh', ...argsRc] : argsRc);
      return '';
    }

    Process results = await shell.start('start', argsRc,
        mode: ProcessStartMode.normal, runInShell: true);
    return results.stdout.toString();
  }

  /// Shutdown WSL
  Future<String> shutdown() async {
    ProcessResult results = await _runWsl(['--shutdown']);
    return results.stdout;
  }

  /// Start VSCode
  void startVSCode(String distribution, {String path = ''}) async {
    String codeCmd = prefs.getString('VSCodeCmd') ?? 'code';
    if (codeCmd.isEmpty) {
      codeCmd = 'code';
    }

    List<String> args = _useRemoteWsl
        ? _buildRemoteArgs('wsl', ['-d', distribution, codeCmd])
        : ['wsl', '-d', distribution, codeCmd];
    if (path != '') {
      args.add(path);
    }

    if (Platform.isLinux) {
      await _startLinuxTerminal(_useRemoteWsl ? ['ssh', ...args] : args);
      return;
    }

    shell.start('start', args, mode: ProcessStartMode.normal, runInShell: true);
  }

  /// Write wslconfig file
  void writeConfig(String text) async {
    if (_useRemoteWsl) {
      await _writeRemoteWslConfigText('[wsl2]\n\n$text');
      return;
    }

    File file = File(getWslConfigPath());
    if (!file.existsSync()) {
      file.createSync();
    }
    file.writeAsStringSync('[wsl2]\n\n$text');
  }

  /// Set wslconfig setting
  void setConfig(String parent, String key, String value) async {
    if (_useRemoteWsl) {
      String text = await _readRemoteWslConfigText();

      // Check if parent exists
      if (text.contains('[$parent]')) {
        // Check if key exists with regeex
        RegExp regex = RegExp('$key[ ]*=');
        if (regex.hasMatch(text)) {
          // Replace key value
          text = text.replaceAll(RegExp('$key[ ]*=(.*)'), '$key = $value');
        } else {
          // Add key value
          text = text.replaceAll('[$parent]', '[$parent]\n$key = $value');
        }
      } else {
        // Add parent and key value
        text += '\n[$parent]\n$key = $value';
      }

      await _writeRemoteWslConfigText(text);
      return;
    }

    File file = File(getWslConfigPath());
    if (!file.existsSync()) {
      file.createSync();
    }
    String text = file.readAsStringSync();

    // Check if parent exists
    if (text.contains('[$parent]')) {
      // Check if key exists with regeex
      RegExp regex = RegExp('$key[ ]*=');
      if (regex.hasMatch(text)) {
        // Replace key value
        text = text.replaceAll(RegExp('$key[ ]*=(.*)'), '$key = $value');
      } else {
        // Add key value
        text = text.replaceAll('[$parent]', '[$parent]\n$key = $value');
      }
    } else {
      // Add parent and key value
      text += '\n[$parent]\n$key = $value';
    }

    // Write to file
    file.writeAsStringSync(text);
  }

  /// Read wslconfig file
  Future<Map<String, String>> readConfig() async {
    if (_useRemoteWsl) {
      Map<String, String> config = {};
      String key = '', value = '';
      String text = await _readRemoteWslConfigText();
      List<String> lines = text.split('\n');

      for (var line in lines) {
        if (line.isNotEmpty && line.contains('=')) {
          key = line.substring(0, line.indexOf('='));
          key = key.replaceAll(' ', '');
          value = line.substring(line.indexOf('=') + 1, line.length);
          value = value.replaceAll(' ', '');
          config[key] = value;
        }
      }
      return config;
    }

    File file = File(getWslConfigPath());
    if (!file.existsSync()) {
      file.createSync();
    }

    Map<String, String> config = {};
    String key = '', value = '';
    List<String> lines = await file.readAsLines();

    for (var line in lines) {
      if (line.isNotEmpty && line.contains('=')) {
        key = line.substring(0, line.indexOf('='));
        key = key.replaceAll(' ', '');
        value = line.substring(line.indexOf('=') + 1, line.length);
        value = value.replaceAll(' ', '');
        config[key] = value;
      }
    }
    return config;
  }

  /// Open wslconfig file
  void editConfig() async {
    if (_useRemoteWsl) {
      Notify.message(
          'Remote .wslconfig editing is not supported via local editor. Change values in Settings and Save.');
      return;
    }

    String editor = prefs.getString('Editor') ?? 'notepad.exe';
    shell.start('start', ['""', editor, getWslConfigPath()],
        mode: ProcessStartMode.normal, runInShell: true);
  }

  Future<bool> _startLinuxTerminal(List<String> command) async {
    final launchAttempts = <List<String>>[
      ['xdg-terminal-exec', ...command],
      ['kgx', ...command],
      ['kitty', ...command],
      ['alacritty', '-e', ...command],
      ['wezterm', 'start', '--', ...command],
      ['x-terminal-emulator', '-e', ...command],
      ['gnome-terminal', '--', ...command],
      ['konsole', '-e', ...command],
      ['xfce4-terminal', '-x', ...command],
      ['xterm', '-e', ...command],
    ];

    for (final attempt in launchAttempts) {
      try {
        await shell.start(
          attempt.first,
          attempt.sublist(1),
          mode: ProcessStartMode.detached,
        );
        return true;
      } catch (_) {
        continue;
      }
    }

    await _showMissingTerminalDialog();
    return false;
  }

  Future<void> _showMissingTerminalDialog() async {
    final rootContext = GlobalVariable.infobox.currentContext;
    if (rootContext == null) {
      Notify.message(
          'No supported terminal emulator found. Install one (for example: xterm, gnome-terminal, or kitty).');
      return;
    }

    await showDialog(
      useRootNavigator: false,
      context: rootContext,
      builder: (context) {
        return ContentDialog(
          title: const Text('Terminal Not Found'),
          content: const Text(
            'No supported terminal emulator was found.\n\n'
            'Install one of these and try again:\n'
            '- xterm\n'
            '- gnome-terminal\n'
            '- kitty\n\n'
            'Example install command:\n'
            'sudo apt update && sudo apt install -y xterm',
          ),
          actions: [
            Button(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  String _windowsPathToSftpUriPath(String windowsPath) {
    final normalized = windowsPath.replaceAll('\\', '/');
    if (normalized.length > 2 && normalized[1] == ':') {
      return '/${normalized[0]}:${normalized.substring(2)}';
    }
    return '/$normalized';
  }

  /// Start Explorer
  void startExplorer(String distribution) async {
    if (_useRemoteWsl) {
      if (Platform.isLinux) {
        final remotePath = _windowsPathToSftpUriPath(
          _remoteDefaultInstallPath(distribution),
        );
        final uri = 'sftp://$_remoteTarget$remotePath';
        await shell.start('xdg-open', [uri],
            mode: ProcessStartMode.detached, runInShell: false);
        return;
      }

      await shell.run(
        'ssh',
        _buildRemoteArgs(
            'explorer.exe', [_remoteDefaultInstallPath(distribution)]),
        runInShell: false,
      );
      return;
    }

    final path = getInstancePath(distribution).path;
    if (Platform.isWindows) {
      await shell.start('start', ['explorer.exe', path],
          mode: ProcessStartMode.normal, runInShell: true);
      return;
    }

    await shell.start('xdg-open', [path],
        mode: ProcessStartMode.detached, runInShell: false);
  }

  /// Start Windows Terminal or PowerShell
  void startWindowsTerminal(String distribution) async {
    List<String> launchWslHome = _useRemoteWsl
        ? _buildRemoteArgs('wsl', ['-d', distribution, '--cd', '~'])
        : ['wsl', '-d', distribution, '--cd', '~'];

    if (_useRemoteWsl && Platform.isLinux) {
      await _startLinuxTerminal(['ssh', ...launchWslHome]);
      return;
    }

    try {
      // Run windows terminal in same window wt -w 0 nt
      var args = ['wt', '-w', '0', 'nt'];
      args.addAll(launchWslHome);

      await shell.run('start', args);
    } catch (_) {
      // Windows Terminal not installed
      Notify.message('openwithwt-not-found-error'.i18n());

      var args = ['powershell', '-noexit', '-command', launchWslHome.join(' ')];
      await shell.run('start', args, runInShell: true);
    }
  }

  /// Copy a WSL distro by name
  Future<String> copy(String distribution, String newName) async {
    String exportPath;
    if (_useRemoteWsl) {
      exportPath = _remoteStagingPath(distribution, '$distribution.ext4');
      await _ensureRemoteDirectory(_remoteParentPath(exportPath));
    } else {
      exportPath = getInstancePath(distribution).file('$distribution.ext4');
    }

    // Copy
    String exportRes = await export(distribution, exportPath);
    String importRes = await import(
      newName,
      _useRemoteWsl ? '' : getInstancePath(newName).path,
      exportPath,
    );

    // Cleanup, delete file
    if (_useRemoteWsl) {
      await shell.run(
        'ssh',
        _buildRemoteArgs('cmd', ['/c', 'del', '/q', '"$exportPath"']),
        runInShell: false,
      );
    } else {
      File file = File(exportPath);
      if (file.existsSync()) {
        file.deleteSync();
      }
    }
    return '$exportRes $importRes';
  }

  /// Copy a WSL distro by name and vhd
  Future<String> copyVhd(String name, String newName) async {
    if (_useRemoteWsl) {
      String vhdPath = '${_remoteDefaultInstallPath(name)}\\ext4.vhdx';
      String copyPath = _remoteStagingPath(name, 'ext4.copy.vhdx');

      await _ensureRemoteDirectory(_remoteParentPath(copyPath));
      ProcessResult copyResult = await shell.run(
        'ssh',
        _buildRemoteArgs('cmd',
            ['/c', 'copy', '/Y', '"$vhdPath"', '"$copyPath"']),
        runInShell: false,
      );

      if (copyResult.exitCode != 0) {
        return 'File not found';
      }

      String importRes = await import(newName, '', copyPath, isVhd: true);

      await shell.run(
        'ssh',
        _buildRemoteArgs('cmd', ['/c', 'del', '/q', '"$copyPath"']),
        runInShell: false,
      );
      return importRes;
    }

    String vhdPath = getInstancePath(name).file('ext4.vhdx');
    String copyPath = getInstancePath(name).file('ext4.copy.vhdx');
    // Copy path to new location so instance doesn't have to be stopped
    File file = File(vhdPath);
    if (file.existsSync()) {
      file.copySync(copyPath);
    } else {
      return 'File not found';
    }

    String importRes = await import(
        newName, getInstancePath(newName).path, copyPath,
        isVhd: true);

    // Cleanup, delete file
    File file2 = File(copyPath);
    if (file2.existsSync()) {
      file2.deleteSync();
    }
    return importRes;
  }

  /// Export a WSL distro by name
  Future<String> export(String distribution, String location) async {
    ProcessResult results = await _runWsl(['--export', distribution, location],
        stdoutEncoding: null, stderrEncoding: null);

    // Check if the export command was successful
    if (results.exitCode != 0) {
      String errorMsg = utf8Convert(results.stderr ?? []);
      throw Exception(
          'WSL export failed with exit code ${results.exitCode}: $errorMsg');
    }

    return utf8Convert(results.stdout);
  }

  /// Remove a WSL distro by name
  Future<String> remove(String distribution) async {
    ProcessResult results = await _runWsl(['--unregister', distribution],
        stdoutEncoding: null, stderrEncoding: null);

    // Check if the remove command was successful
    if (results.exitCode != 0) {
      String errorMsg = utf8Convert(results.stderr ?? []);
      throw Exception(
          'WSL unregister failed with exit code ${results.exitCode}: $errorMsg');
    }

    // Check if folder is empty and delete
    if (!_useRemoteWsl) {
      String path = getInstancePath(distribution).path;
      // Wait 10 seconds in async then delete for Windows to release file
      Future.delayed(const Duration(seconds: 10), () {
        Directory dir = Directory(path);
        if (dir.existsSync()) {
          if (dir.listSync().isEmpty) {
            dir.deleteSync(recursive: true);
          }
        }
      });
    }
    return utf8Convert(results.stdout);
  }

  /// Install a WSL distro by name
  Future<String> install(String distribution) async {
    ProcessResult results = await _runWsl(['--install', '-d', distribution]);
    return results.stdout;
  }

  List<String> resultQueue = [];

  /// Get the current cached output
  String getCurrentOutput() {
    String tmp = resultQueue.join('\n');
    resultQueue = [];
    return tmp;
  }

  /// Executes a command list in a WSL distro
  Future<List<int>> execCmds(
    String distribution,
    List<String> cmds, {
    String? user,
    required Function(String) onMsg,
    required Function onDone,
    bool showOutput = true,
  }) async {
    List<int> processes = [];
    Process result = await _startWsl(
      ['-d', distribution, '-u', user ?? 'root'],
      mode: ProcessStartMode.normal,
      runInShell: !_useRemoteWsl,
      allocateTty: _useRemoteWsl,
    );

    Timer currentWaiter = Timer(const Duration(seconds: 60), () {
      result.kill();
      onDone();
    });

    result.stdout
        .cast<List<int>>()
        .transform(const Utf8Decoder())
        .listen((String line) {
      resultQueue.add(line);
      onMsg(line);
      currentWaiter.cancel();
      // No new output within the last 30 seconds
      currentWaiter = Timer(const Duration(seconds: 15), () {
        result.kill();
        onDone();
      });
    });

    // Log output to file
    result.stdin.writeln('script -B /tmp/currentsessionlog -f');
    // Start windows with output
    await _startWsl(
      [
        '-d',
        distribution,
        '-u',
        user ?? 'root',
        'tail',
        '-n',
        '+1',
        '-f',
        '/tmp/currentsessionlog'
      ],
      mode: showOutput ? ProcessStartMode.detached : ProcessStartMode.normal,
      runInShell: !_useRemoteWsl,
      allocateTty: _useRemoteWsl,
    );

    // Delay to allow tail to start
    await Future.delayed(const Duration(milliseconds: 500));

    for (var cmd in cmds) {
      result.stdin.writeln(cmd);
    }
    return processes;
  }

  /// Executes a command list in a WSL distro and open a terminal
  Future<Process> runCmds(
    String distribution,
    List<String> cmds, {
    String? user,
  }) async {
    // Write commands to /tmp/cmds
    Process fileProcess = await _startWsl(
      ['-d', distribution, '-u', user ?? 'root'],
      mode: ProcessStartMode.normal,
      runInShell: !_useRemoteWsl,
      allocateTty: _useRemoteWsl,
    );

    fileProcess.stdin.writeln('echo "#!/bin/bash" > /tmp/wdmcmds');
    for (var cmd in cmds) {
      cmd = cmd.replaceAll('"', '\\"');
      fileProcess.stdin.writeln('echo "$cmd" >> /tmp/wdmcmds');
    }
    var waitCmd = 'read -n1 -r -p \\"\n\nDone running the action. '
        'Press any key to exit...\\" key';
    fileProcess.stdin.writeln('echo "$waitCmd" >> /tmp/wdmcmds');

    // Wait for commands to be written
    await Future.delayed(const Duration(milliseconds: 500));

    // Execute commands in /tmp/cmds
    List<String> args = [
      '-d',
      distribution,
      '-u',
      user ?? 'root',
      '/bin/bash',
      '/tmp/wdmcmds'
    ];

    Process results = await _startWsl(
      args,
      runInShell: !_useRemoteWsl,
      mode: ProcessStartMode.detached,
      allocateTty: _useRemoteWsl,
    );

    return results;
  }

  /// Executes a command in a WSL distro and returns the output
  Future<String> execCmdAsRoot(String distribution, String cmd) async {
    List<String> args = ['--distribution', distribution, '-u', 'root'];
    for (var arg in cmd.split(' ')) {
      args.add(arg);
    }
    ProcessResult results = await _runWsl(args,
        runInShell: true, stdoutEncoding: utf8, stderrEncoding: utf8);
    return results.stdout;
  }

  /// Executes a command in a WSL distro. passwd will open a shell
  Future<List<int>> exec(String distribution, List<String> cmds) async {
    List<String> args;
    List<int> processes = [];
    int exitCode;
    for (String cmd in cmds) {
      if (cmd.contains('passwd')) {
        args = _useRemoteWsl
            ? _buildRemoteArgs('wsl', ['-d', distribution], allocateTty: true)
            : ['wsl', '-d', distribution];
        cmd.split(' ').forEach((String arg) {
          args.add(arg);
        });
        if (_useRemoteWsl && Platform.isLinux) {
          await _startLinuxTerminal(['ssh', ...args]);
          exitCode = 0;
        } else {
          Process result = await shell.start('start', args,
              mode: ProcessStartMode.normal, runInShell: true);
          exitCode = await result.exitCode;
        }
        processes.add(exitCode);
      } else {
        args = ['-d', distribution];
        cmd.split(' ').forEach((String arg) {
          args.add(arg);
        });
        ProcessResult result = await _runWsl(args, runInShell: false);
        exitCode = result.exitCode;
        processes.add(exitCode);
      }
    }
    return processes;
  }

  /// Restart WSL
  Future<String> restart() async {
    ProcessResult results = await _runWsl(['--shutdown']);
    results = await _runWsl(['--shutdown']);
    return results.stdout;
  }

  /// Import a WSL distro by name
  Future<String> import(
      String distribution, String installLocation, String filename,
      {bool isVhd = false}) async {
    if (_useRemoteWsl) {
      if (installLocation.trim().isEmpty) {
        installLocation = _remoteDefaultInstallPath(distribution);
      }
      await _ensureRemoteDirectory(_remoteParentPath(installLocation));
      await _ensureRemoteDirectory(installLocation);
      if (File(filename).existsSync()) {
        filename = await _stageLocalFileToRemote(
          filename,
          _remoteStagingPath(distribution, filename),
        );
      }
    } else {
      if (installLocation == '') {
        installLocation = getInstancePath(distribution).path;
      } else {
        installLocation = SafePath(installLocation).path;
      }
    }
    ProcessResult results;
    if (isVhd) {
      results = await _runWsl(
          ['--import', distribution, installLocation, filename, '--vhd'],
          stdoutEncoding: null, stderrEncoding: null);
    } else {
      results = await _runWsl(
          ['--import', distribution, installLocation, filename],
          stdoutEncoding: null, stderrEncoding: null);
    }

    // Check if the import command was successful
    if (results.exitCode != 0) {
      String errorMsg = utf8Convert(results.stderr ?? []);
      throw Exception(
          'WSL import failed with exit code ${results.exitCode}: $errorMsg');
    }

    return utf8Convert(results.stdout);
  }

  /// Import a WSL distro by name
  Future<dynamic> create(String distribution, String filename,
      String installPath, Function(String) status,
      {bool image = false, bool isVhd = false}) async {
    if (_useRemoteWsl) {
      if (installPath.trim().isEmpty) {
        installPath = _remoteDefaultInstallPath(distribution);
      }
      await _ensureRemoteDirectory(_remoteParentPath(installPath));
      await _ensureRemoteDirectory(installPath);
    } else {
      if (installPath == '') {
        installPath = getInstancePath(distribution).path;
      } else {
        installPath = SafePath(installPath).path;
      }
    }

    // Download
    var dataPath = getDataPath()..cd('distros');
    String downloadPath = dataPath.file('$filename.tar.gz');
    String downloadPathTmp = dataPath.file('$filename.tar.gz.tmp');
    bool fileExists = await File(downloadPath).exists();
    if (!image && distroRootfsLinks[filename] != null && !fileExists) {
      String url = distroRootfsLinks[filename]!;
      // Download file
      try {
        var downloader = ChunkedDownloader(
            url: url,
            saveFilePath: downloadPathTmp,
            onProgress: (int count, int total, double speed) {
              status('${'downloading-text'.i18n()}'
                  ' ${(count / total * 100).toStringAsFixed(0)}%');
            })
          ..start();
        // Await download
        while (!downloader.done) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
        File file = File(downloadPathTmp);
        file.rename(downloadPath);
        status('${'downloaded-text'.i18n()} $filename');
      } catch (error) {
        status('${'errordownloading-text'.i18n()} $filename');
      }
    }

    // Downloaded or extracted
    if (!image && distroRootfsLinks[filename] == null) {
      downloadPath = filename;
    }

    if (_useRemoteWsl) {
      downloadPath = await _stageLocalFileToRemote(
        downloadPath,
        _remoteStagingPath(distribution, downloadPath),
      );
    }

    // Create from local file
    List<String> args = ['--import', distribution, installPath, downloadPath];
    if (isVhd) {
      args.add('--vhd');
    }

    ProcessResult results = await _runWsl(args, stdoutEncoding: null);

    return results;
  }

  var lastDistroList = Instances([], []);

  /// Returns list of WSL distros
  Future<Instances> list(bool showDocker) async {
    ProcessResult results;
    try {
      results = await _runWsl(['--list', '--quiet'], stdoutEncoding: null)
          .timeout(_useRemoteWsl ? _remoteListTimeout : const Duration(days: 1));
    } on TimeoutException {
      if (_useRemoteWsl) {
        throw Exception(
            'Remote WSL host unreachable: timed out while connecting to $remoteTargetLabel.');
      }
      throw Exception('WSL list timed out.');
    } on ProcessException catch (e) {
      if (_useRemoteWsl) {
        throw Exception(
            'Remote WSL SSH connection failed for $remoteTargetLabel: ${e.message}');
      }
      rethrow;
    }

    String output = utf8Convert(results.stdout);
    String stderr = utf8Convert(results.stderr is List<int>
      ? results.stderr as List<int>
      : utf8.encode(results.stderr?.toString() ?? ''));

    if (results.exitCode != 0) {
      final combined = [stderr.trim(), output.trim()]
        .where((part) => part.isNotEmpty)
        .join('\n');

      final lowerCombined = combined.toLowerCase();
      final hasAskpassIssue = lowerCombined.contains('ssh_askpass') ||
        lowerCombined.contains('askpass') ||
        lowerCombined.contains('libcrypto');
      if (hasAskpassIssue && _useRemoteWsl) {
      throw Exception(
        'Remote SSH authentication is not available in non-interactive mode for $remoteTargetLabel. Configure key-based SSH authentication (or an ssh-agent) and retry.\n$combined');
      }

      // Keep existing UX for genuinely empty setups while surfacing real failures.
      final likelyNoDistro =
        lowerCombined.contains('no installed distributions') ||
          lowerCombined.contains('distributions can be installed') ||
          lowerCombined.contains('keine installierten distributionen') ||
          lowerCombined.contains(
            'distribution kann mit folgenden befehlen installiert werden');
      if (likelyNoDistro) {
      lastDistroList = Instances([], []);
      return lastDistroList;
      }

      throw Exception(combined.isEmpty
        ? 'Failed to list WSL distros (exit code ${results.exitCode}).'
        : combined);
    }
    List<String> list = [];
    bool wslInstalled = true;
    // Check if wsl is installed
    if (output.contains('wsl.exe') || output.contains('ProcessException')) {
      wslInstalled = false;
    }
    if (wslInstalled) {
      if (output.contains('ERROR_FILE_NOT_FOUND')) {
        return lastDistroList;
      }
      output.split('\n').forEach((line) {
        final cleanLine = _sanitizeDistroName(line);
        var dockerfilter = showDocker
            ? true
            : (!cleanLine.startsWith('docker-desktop-data') &&
                !cleanLine.startsWith('docker-desktop'));
        // Filter out docker data
        if (cleanLine.isNotEmpty && dockerfilter) {
          list.add(cleanLine);
        }
      });
      List<String> running;
      try {
        running = await listRunning();
      } catch (_) {
        running = lastDistroList.running;
      }
      lastDistroList = Instances(list, running);
      return Instances(list, running);
    } else {
      return Instances(['wslNotInstalled'], []);
    }
  }

  /// Clean up WSL distros. Compacting the VHDX file.
  Future<String> cleanup(String distribution,
      {Function(String)? onProgress}) async {
    if (_useRemoteWsl) {
      final remoteInstallPath = _remoteInstallPathFor(distribution);
      final exportPath = _remoteStagingPath(distribution, 'cleanup.ext4');
      await _ensureRemoteDirectory(_remoteParentPath(exportPath));

      try {
        onProgress?.call('stopping-distro'.i18n());
        await stop(distribution);

        onProgress?.call('exportinginstance-text'.i18n([distribution]));
        await export(distribution, exportPath);

        onProgress?.call('deletinginstance-text'.i18n([distribution]));
        await remove(distribution);

        onProgress?.call('importinginstance-text'.i18n([distribution]));
        await import(distribution, remoteInstallPath, exportPath);

        await shell.run(
          'ssh',
          _buildRemoteArgs('cmd', ['/c', 'del', '/q', '"$exportPath"']),
          runInShell: false,
        );

        prefs.setString('Path_$distribution', remoteInstallPath);
        return 'Cleanup completed successfully';
      } catch (error, stack) {
        logError(error, stack, null);
        throw Exception('Cleanup failed: ${error.toString()}');
      }
    }

    var instancePath = getInstancePath(distribution);
    var vhdxPath = instancePath.file('ext4.vhdx');

    // Check if VHDX exists
    bool vhdxExists;
    try {
      vhdxExists = File(vhdxPath).existsSync();
    } on FileSystemException catch (error, stack) {
      logError(error, stack, null);
      vhdxExists = false;
    }

    if (!vhdxExists) {
      throw Exception('VHDX file not found: $vhdxPath');
    }

    try {
      // Step 1: Stop the distribution
      onProgress?.call('stopping-distro'.i18n());
      await stop(distribution);

      // Step 2: Create diskpart script
      onProgress?.call('compacting-vdisk'.i18n());
      String scriptContent = 'select vdisk file="$vhdxPath"\n'
          'attach vdisk readonly\n'
          'compact vdisk\n'
          'detach vdisk';

      // Use temp path for script after sanitizing distro name
      final safeDistribution =
          distribution.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      String scriptPath = getTmpPath().file('diskpart_$safeDistribution.txt');
      File(scriptPath).writeAsStringSync(scriptContent);

      try {
        // Step 3: Run diskpart with admin privileges
        // We use PowerShell to elevate the process and capture its exit code
        var result = await shell.run('powershell', [
          '-Command',
          '\$p = Start-Process diskpart -ArgumentList "/s \\"$scriptPath\\"" -Verb RunAs -Wait -PassThru; exit \$p.ExitCode'
        ]);

        if (result.exitCode != 0) {
          throw Exception(
              'Diskpart failed with exit code ${result.exitCode}: ${result.stderr}');
        }
      } finally {
        // Step 4: Cleanup script
        final scriptFile = File(scriptPath);
        if (scriptFile.existsSync()) {
          scriptFile.deleteSync();
        }
      }

      return 'Cleanup completed successfully';
    } catch (error, stack) {
      logError(error, stack, null);
      throw Exception('Cleanup failed: ${error.toString()}');
    }
  }

  /// Returns list of WSL distros
  Future<List<String>> listRunning() async {
    ProcessResult results;
    try {
      results =
          await _runWsl(['--list', '--running', '--quiet'], stdoutEncoding: null)
              .timeout(_useRemoteWsl
                  ? _remoteListTimeout
                  : const Duration(days: 1));
    } on TimeoutException {
      if (_useRemoteWsl) {
        return lastDistroList.running;
      }
      rethrow;
    } on ProcessException {
      if (_useRemoteWsl) {
        return lastDistroList.running;
      }
      rethrow;
    }

    String output = utf8Convert(results.stdout);
    String stderr = utf8Convert(results.stderr is List<int>
      ? results.stderr as List<int>
      : utf8.encode(results.stderr?.toString() ?? ''));

    if (results.exitCode != 0) {
      final combined = [stderr.trim(), output.trim()]
        .where((part) => part.isNotEmpty)
        .join('\n');
      throw Exception(combined.isEmpty
        ? 'Failed to list running WSL distros (exit code ${results.exitCode}).'
        : combined);
    }

    List<String> list = [];
    output.split('\n').forEach((line) {
      final cleanLine = _sanitizeDistroName(line);
      // Filter out docker data
      if (cleanLine.isNotEmpty) {
        list.add(cleanLine);
      }
    });
    return list;
  }

  String _sanitizeDistroName(String value) {
    return value
        .replaceAll('\u0000', '')
        .replaceAll('\r', '')
        .replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '')
        .trim();
  }

  /// Returns list of downloadable WSL distros
  Future<List<String>> getDownloadable(
      String repo, Function(String) onError) async {
    // Get list of distros from git
    distroRootfsLinks = await App().getDistroLinks();
    // Get list of distros from custom repo link and try to format
    try {
      await Dio().get(repo).then((value) => {
            value.data.split('\n').forEach((line) {
              if (line.contains('tar.gz') && line.contains('href=')) {
                var parts = line.split(RegExp(r'href=["' ']'));
                if (parts.length < 2) return;
                String filename = parts[1].split(RegExp(r'["' ']'))[0];

                if (!filename.endsWith('.tar.gz')) return;

                String name = filename
                    .replaceAll('.tar.gz', '')
                    .replaceAll('1_amd64', '')
                    .replaceAll(RegExp(r'-|_'), ' ')
                    .replaceAllMapped(RegExp(r' .|^.'),
                        (Match m) => m[0].toString().toUpperCase());
                distroRootfsLinks.addAll({name: repo + filename});
              }
            })
          });
    } catch (e) {
      onError(e.toString());
    }
    List<String> list = [];
    list.addAll(distroRootfsLinks.keys);
    return list;
  }

  /// Move WSL distro to another location by [distro] and [newPath].
  /// Returns [ProcessResult] of the command.
  Future<String> move(String distro, String newPath) async {
    if (_useRemoteWsl) {
      String exportFilePath = _remoteStagingPath(distro, 'export.ext4');
      await _ensureRemoteDirectory(_remoteParentPath(exportFilePath));

      await export(distro, exportFilePath);
      await remove(distro);

      try {
        var res = await import(distro, newPath, exportFilePath);
        await shell.run(
          'ssh',
          _buildRemoteArgs(
              'cmd', ['/c', 'del', '/q', '"$exportFilePath"']),
          runInShell: false,
        );

        final remotePath = newPath.trim().isEmpty
            ? _remoteDefaultInstallPath(distro)
            : newPath;
        prefs.setString('Path_$distro', remotePath);
        return res;
      } catch (e) {
        throw Exception(
            "Import failed: $e. Your data is safe in: $exportFilePath. Please do not delete this file.");
      }
    }

    SafePath path = SafePath(newPath);
    String exportFilePath = path.file('export.ext4');

    // Check if new path is same as old path (normalize + absolute paths, compare case-insensitive on Windows)
    String currentPath = getInstancePath(distro).path;
    String canonicalCurrent = p.canonicalize(currentPath);
    String canonicalNew = p.canonicalize(path.path);
    bool samePath;
    if (Platform.isWindows) {
      samePath = canonicalCurrent.toLowerCase() == canonicalNew.toLowerCase();
    } else {
      samePath = canonicalCurrent == canonicalNew;
    }
    if (samePath) {
      throw Exception(
          "Cannot move '$distro': new path must be different from current path ($canonicalCurrent).");
    }

    // Export
    await export(distro, exportFilePath);

    // Verify export
    File exportFile = File(exportFilePath);

    // Get original VHDX size to determine safety threshold
    int vhdxSize = 0;
    try {
      File vhdxFile = File(getInstancePath(distro).file('ext4.vhdx'));
      if (vhdxFile.existsSync()) {
        vhdxSize = vhdxFile.lengthSync();
      }
    } catch (e) {
      logDebug('Could not get VHDX size for $distro: $e', null, null);
    }

    // Determine minimum safe size based on original VHDX
    // If VHDX is large (>1GB), expect at least 10MB export to catch "header-only" corruptions.
    // Otherwise, expect at least 1MB to support minimal distros like Alpine.
    int minSize =
        (vhdxSize > 1024 * 1024 * 1024) ? 10 * 1024 * 1024 : 1024 * 1024;

    if (!exportFile.existsSync() || exportFile.lengthSync() < minSize) {
      if (exportFile.existsSync()) {
        exportFile.deleteSync();
      }
      throw Exception(
          "Export failed or file too small (<${minSize ~/ (1024 * 1024)}MB). Aborting move to prevent data loss.");
    }

    // Set recovery marker
    await prefs.setString('MoveOp_Distro', distro);
    await prefs.setString('MoveOp_BackupPath', exportFilePath);

    // Remove old
    await remove(distro);

    // Import new
    try {
      var res = await import(distro, newPath, exportFilePath);

      // Cleanup export file only if import succeeded
      await exportFile.delete();

      // Update preference
      prefs.setString('Path_$distro', newPath);

      // Clear recovery marker
      await prefs.remove('MoveOp_Distro');
      await prefs.remove('MoveOp_BackupPath');

      return res;
    } catch (e) {
      throw Exception(
          "Import failed: $e. Your data is safe in: $exportFilePath. Please do not delete this file.");
    }
  }

  /// Convert process bytes to readable text while preserving valid UTF-8.
  String utf8Convert(List<int> bytes) {
    if (bytes.isEmpty) {
      return '';
    }

    final decoded = const Utf8Decoder(allowMalformed: true).convert(bytes);
    // Keep common whitespace while stripping other control characters.
    return decoded.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');
  }

  /// Change setting in wsl.conf with key and value
  Future<bool> setSetting(
      String distro, String parent, String key, String value) async {
    // Read trigger script from assets
    String script = await rootBundle.loadString('assets/scripts/settings.bash');
    script = script.replaceAll(RegExp(r'^#.*\n', multiLine: true), '');
    script = script.replaceAll('PARENT', parent);
    script = script.replaceAll('KEY', key);
    script = script.replaceAll('VALUE', value);
    List<String> scriptLines = script.split('\n');

    // Execute trigger script
    await execCmds(distro, scriptLines,
        onMsg: (msg) {}, onDone: () {}, showOutput: false);
    return true;
  }

  /// Get wsl.conf settings
  Future<Map<String, Map<String, String>>> getWSLConf(String distro) async {
    String output = await execCmdAsRoot(distro, 'cat /etc/wsl.conf');
    Map<String, Map<String, String>> config = {};
    String currentSection = '';

    for (String line in output.split('\n')) {
      line = line.trim();
      if (line.startsWith('[') && line.endsWith(']')) {
        currentSection = line.substring(1, line.length - 1);
        config[currentSection] = {};
      } else if (line.contains('=')) {
        List<String> parts = line.split('=');
        String key = parts[0].trim();
        String value = parts.sublist(1).join('=').trim();
        if (currentSection.isNotEmpty) {
          config[currentSection]![key] = value;
        }
      }
    }
    return config;
  }

  /// Get default user of a distro
  Future<String> getDefaultUser(String distribution) async {
    ProcessResult result = await _runWsl(['-d', distribution, '-e', 'whoami'],
        stdoutEncoding: null, stderrEncoding: null);

    if (result.exitCode != 0) {
      logDebug('Failed to get default user for $distribution', null, null);
      return 'root';
    }
    return utf8Convert(result.stdout).trim();
  }
}
