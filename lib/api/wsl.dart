import 'dart:async';
import 'dart:io';
import 'dart:convert' show Utf8Decoder, utf8;
import 'package:chunked_downloader/chunked_downloader.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:localization/localization.dart';

import 'package:flutter/services.dart' show rootBundle;
import 'package:wsl2distromanager/api/app.dart';
import 'package:wsl2distromanager/api/safe_paths.dart';
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
  WSLApi() {
    if (!inited) {
      inited = true;
      App().getDistroLinks();
    }
  }

  /// Get distro size of [distroName] a string with a GB suffix.
  /// Returns null if size is 0.
  /// e.g. "2.00 GB"
  String? getSize(String distroName) {
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
  void mkRootDir({String path = defaultPath}) {
    SafePath(path);
  }

  /// Install WSL
  void installWSL() async {
    Process.start(
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
    List<String> args = ['wsl', '-d', distribution];
    if (startPath != '') {
      args.addAll(['--cd', startPath]);
    }
    if (startUser != '') {
      args.addAll(['--user', startUser]);
    }
    if (startCmd != '') {
      for (String cmd in startCmd.split(' ')) {
        args.add(cmd);
      }
      // Run shell to keep open
      args.add(';/bin/sh');
    }
    await Process.start('start', args,
        mode: ProcessStartMode.detached, runInShell: true);

    if (kDebugMode) {
      print("Done starting $distribution");
    }
  }

  /// Stop a WSL distro by name
  Future<String> stop(String distribution) async {
    ProcessResult results =
        await Process.run('wsl', ['--terminate', distribution]);
    return results.stdout;
  }

  /// Open bashrc with notepad from WSL
  Future<String> openBashrc(String distribution) async {
    List<String> argsRc = ['wsl', '-d', distribution, 'notepad.exe', '.bashrc'];
    Process results = await Process.start('start', argsRc,
        mode: ProcessStartMode.normal, runInShell: true);
    return results.stdout.toString();
  }

  /// Shutdown WSL
  Future<String> shutdown() async {
    ProcessResult results = await Process.run('wsl', ['--shutdown']);
    return results.stdout;
  }

  /// Start VSCode
  void startVSCode(String distribution, {String path = ''}) async {
    List<String> args = ['wsl', '-d', distribution, 'code'];
    if (path != '') {
      args.add(path);
    }
    Process.start('start', args,
        mode: ProcessStartMode.normal, runInShell: true);
  }

  /// Write wslconfig file
  void writeConfig(String text) async {
    File file = File(getWslConfigPath());
    if (!file.existsSync()) {
      file.createSync();
    }
    file.writeAsStringSync('[wsl2]\n\n$text');
  }

  /// Set wslconfig setting
  void setConfig(String parent, String key, String value) async {
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
    Process.start('start', ['notepad.exe', getWslConfigPath()],
        mode: ProcessStartMode.normal, runInShell: true);
  }

  /// Start Explorer
  void startExplorer(String distribution) async {
    await Process.start(
        'start', ['explorer.exe', getInstancePath(distribution).path],
        mode: ProcessStartMode.normal, runInShell: true);
  }

  /// Start Windows Terminal\
  /// *(falls back to PowerShell on exception)*
  void startWindowsTerminal(String distribution) async {
    List<String> launchWslHome = ['wsl', '-d', distribution, '--cd', '~'];
    try {
      await Process.start('wt', launchWslHome);
    } catch (_) {
      // Windows Terminal not installed
      Notify.message('openwithwt-not-found-error'.i18n());

      var args = ['powershell', '-noexit', '-command', launchWslHome.join(' ')];
      await Process.run('start', args, runInShell: true);
    }
  }

  /// Copy a WSL distro by name
  Future<String> copy(String distribution, String newName) async {
    String exportPath =
        getInstancePath(distribution).file('$distribution.ext4');
    // Copy
    String exportRes = await export(distribution, exportPath);
    String importRes =
        await import(newName, getInstancePath(newName).path, exportPath);

    // Cleanup, delete file
    File file = File(exportPath);
    if (file.existsSync()) {
      file.deleteSync();
    }
    return '$exportRes $importRes';
  }

  /// Copy a WSL distro by name and vhd
  Future<String> copyVhd(String name, String newName) async {
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
    ProcessResult results = await Process.run(
        'wsl', ['--export', distribution, location],
        stdoutEncoding: null);
    return utf8Convert(results.stdout);
  }

  /// Remove a WSL distro by name
  Future<String> remove(String distribution) async {
    ProcessResult results =
        await Process.run('wsl', ['--unregister', distribution]);

    // Check if folder is empty and delete
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
    return results.stdout;
  }

  /// Install a WSL distro by name
  Future<String> install(String distribution) async {
    ProcessResult results =
        await Process.run('wsl', ['--install', '-d', distribution]);
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
    Process result = await Process.start(
        'wsl', ['-d', distribution, '-u', user ?? 'root'],
        mode: ProcessStartMode.normal, runInShell: true);

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
    await Process.start(
        'wsl',
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
        runInShell: true);

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
    Process fileProcess = await Process.start(
        'wsl', ['-d', distribution, '-u', user ?? 'root'],
        mode: ProcessStartMode.normal, runInShell: true);

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

    Process results = await Process.start('wsl', args,
        runInShell: true, mode: ProcessStartMode.detached);

    return results;
  }

  /// Executes a command in a WSL distro and returns the output
  Future<String> execCmdAsRoot(String distribution, String cmd) async {
    List<String> args = ['--distribution', distribution, '-u', 'root'];
    for (var arg in cmd.split(' ')) {
      args.add(arg);
    }
    ProcessResult results = await Process.run('wsl', args,
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
        args = ['wsl', '-d', distribution];
        cmd.split(' ').forEach((String arg) {
          args.add(arg);
        });
        Process result = await Process.start('start', args,
            mode: ProcessStartMode.normal, runInShell: true);
        exitCode = await result.exitCode;
        processes.add(exitCode);
      } else {
        args = ['-d', distribution];
        cmd.split(' ').forEach((String arg) {
          args.add(arg);
        });
        ProcessResult result =
            await Process.run('wsl', args, runInShell: false);
        exitCode = result.exitCode;
        processes.add(exitCode);
      }
    }
    return processes;
  }

  /// Restart WSL
  Future<String> restart() async {
    ProcessResult results = await Process.run('wsl', ['--shutdown']);
    results = await Process.run('wsl', ['--shutdown']);
    return results.stdout;
  }

  /// Import a WSL distro by name
  Future<String> import(
      String distribution, String installLocation, String filename,
      {bool isVhd = false}) async {
    if (installLocation == '') {
      installLocation = getInstancePath(distribution).path;
    } else {
      installLocation = SafePath(installLocation).path;
    }
    ProcessResult results;
    if (isVhd) {
      results = await Process.run(
          'wsl', ['--import', distribution, installLocation, filename, '--vhd'],
          stdoutEncoding: null);
    } else {
      results = await Process.run(
          'wsl', ['--import', distribution, installLocation, filename],
          stdoutEncoding: null);
    }
    return utf8Convert(results.stdout);
  }

  /// Import a WSL distro by name
  Future<dynamic> create(String distribution, String filename,
      String installPath, Function(String) status,
      {bool image = false}) async {
    if (installPath == '') {
      installPath = getInstancePath(distribution).path;
    } else {
      installPath = SafePath(installPath).path;
    }

    // Download
    String downloadPath = getDistroPath().file('$filename.tar.gz');
    String downloadPathTmp = getDistroPath().file('$filename.tar.gz.tmp');
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

    // Create from local file
    ProcessResult results = await Process.run(
        'wsl', ['--import', distribution, installPath, downloadPath],
        stdoutEncoding: null);

    return results;
  }

  var lastDistroList = Instances([], []);

  /// Returns list of WSL distros
  Future<Instances> list(bool showDocker) async {
    ProcessResult results =
        await Process.run('wsl', ['--list', '--quiet'], stdoutEncoding: null);
    String output = utf8Convert(results.stdout);
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
        var dockerfilter = showDocker
            ? true
            : (!line.startsWith('docker-desktop-data') &&
                !line.startsWith('docker-desktop'));
        // Filter out docker data
        if (line != '' && dockerfilter) {
          list.add(line);
        }
      });
      List<String> running = await listRunning();
      lastDistroList = Instances(list, running);
      return Instances(list, running);
    } else {
      return Instances(['wslNotInstalled'], []);
    }
  }

  /// Clean up WSL distros. Exporting, deleting, and importing.
  Future<String> cleanup(String distribution) async {
    var instancePath = getInstancePath(distribution);
    var file = instancePath.file('export.tar.gz');

    // Export, remove, and import
    await export(distribution, file);
    await remove(distribution);

    return await import(distribution, instancePath.path, file);
  }

  /// Returns list of WSL distros
  Future<List<String>> listRunning() async {
    ProcessResult results = await Process.run(
        'wsl', ['--list', '--running', '--quiet'],
        stdoutEncoding: null);
    String output = utf8Convert(results.stdout);
    List<String> list = [];
    output.split('\n').forEach((line) {
      // Filter out docker data
      if (line != '') {
        list.add(line);
      }
    });
    return list;
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
              if (line.contains('tar.gz"') &&
                  line.contains('href=') &&
                  (line.contains('debian-10') || line.contains('debian-11'))) {
                String name = line
                    .split('href="')[1]
                    .split('"')[0]
                    .toString()
                    .replaceAll('.tar.gz', '')
                    .replaceAll('1_amd64', '')
                    .replaceAll(RegExp(r'-|_'), ' ')
                    .replaceAllMapped(RegExp(r' .|^.'),
                        (Match m) => m[0].toString().toUpperCase());
                distroRootfsLinks.addAll({
                  name: repo + line.split('href="')[1].split('"')[0].toString()
                });
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
    SafePath path = SafePath(newPath);
    await export(distro, path.file('export.ext4'));
    await remove(distro);
    var res = await import(distro, newPath, path.file('export.ext4'));
    await File(path.file('export.ext4')).delete();

    return res;
  }

  /// Convert bytes to human readable string while removing non-ascii characters
  String utf8Convert(List<int> bytes) {
    List<int> utf8Lines = List<int>.from(bytes);
    bool running = true;
    int i = 0;
    while (running) {
      // Check end of string
      if (utf8Lines.length == i) {
        running = false;
        break;
      }
      // Remove non-ascii/unnecessary utf8 characters but keep newline (10)
      if (utf8Lines[i] != 10 && (utf8Lines[i] < 32 || utf8Lines[i] > 122)) {
        utf8Lines.removeAt(i);
        continue;
      }
      i++;
    }
    return utf8.decode(utf8Lines);
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
}
