import 'dart:async';
import 'dart:io';
import 'dart:convert' show Utf8Decoder, utf8;
import 'package:chunked_downloader/chunked_downloader.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
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

  WSLApi({Shell? shell}) : shell = shell ?? ProcessShell() {
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
    List<String> args = [];
    args.addAll(['wsl', '-d', distribution]);
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

    String executable = 'start';
    String? terminal = prefs.getString('Terminal');
    if (terminal != null && terminal.isNotEmpty) {
      executable = terminal;
    }

    await shell.start(executable, args,
        mode: ProcessStartMode.detached, runInShell: true);
    if (kDebugMode) {
      print("Done starting $distribution");
    }
  }

  /// Stop a WSL distro by name
  Future<String> stop(String distribution) async {
    ProcessResult results =
        await shell.run('wsl', ['--terminate', distribution]);
    return results.stdout;
  }

  /// Open bashrc with notepad from WSL
  Future<String> openBashrc(String distribution) async {
    String editor = prefs.getString('Editor') ?? 'notepad.exe';
    List<String> argsRc = ['wsl', '-d', distribution, editor, '.bashrc'];
    Process results = await shell.start('start', argsRc,
        mode: ProcessStartMode.normal, runInShell: true);
    return results.stdout.toString();
  }

  /// Shutdown WSL
  Future<String> shutdown() async {
    ProcessResult results = await shell.run('wsl', ['--shutdown']);
    return results.stdout;
  }

  /// Start VSCode
  void startVSCode(String distribution, {String path = ''}) async {
    List<String> args = ['wsl', '-d', distribution, 'code'];
    if (path != '') {
      args.add(path);
    }
    shell.start('start', args, mode: ProcessStartMode.normal, runInShell: true);
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
    String editor = prefs.getString('Editor') ?? 'notepad.exe';
    shell.start('start', ['""', editor, getWslConfigPath()],
        mode: ProcessStartMode.normal, runInShell: true);
  }

  /// Start Explorer
  void startExplorer(String distribution) async {
    await shell.start(
        'start', ['explorer.exe', getInstancePath(distribution).path],
        mode: ProcessStartMode.normal, runInShell: true);
  }

  /// Start Windows Terminal or PowerShell
  void startWindowsTerminal(String distribution) async {
    List<String> launchWslHome = ['wsl', '-d', distribution, '--cd', '~'];
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
    ProcessResult results = await shell.run(
        'wsl', ['--export', distribution, location],
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
    ProcessResult results = await shell.run(
        'wsl', ['--unregister', distribution],
        stdoutEncoding: null, stderrEncoding: null);

    // Check if the remove command was successful
    if (results.exitCode != 0) {
      String errorMsg = utf8Convert(results.stderr ?? []);
      throw Exception(
          'WSL unregister failed with exit code ${results.exitCode}: $errorMsg');
    }

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
    return utf8Convert(results.stdout);
  }

  /// Install a WSL distro by name
  Future<String> install(String distribution) async {
    ProcessResult results =
        await shell.run('wsl', ['--install', '-d', distribution]);
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
    Process result = await shell.start(
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
    await shell.start(
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
    Process fileProcess = await shell.start(
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

    Process results = await shell.start('wsl', args,
        runInShell: true, mode: ProcessStartMode.detached);

    return results;
  }

  /// Executes a command in a WSL distro and returns the output
  Future<String> execCmdAsRoot(String distribution, String cmd) async {
    List<String> args = ['--distribution', distribution, '-u', 'root'];
    for (var arg in cmd.split(' ')) {
      args.add(arg);
    }
    ProcessResult results = await shell.run('wsl', args,
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
        Process result = await shell.start('start', args,
            mode: ProcessStartMode.normal, runInShell: true);
        exitCode = await result.exitCode;
        processes.add(exitCode);
      } else {
        args = ['-d', distribution];
        cmd.split(' ').forEach((String arg) {
          args.add(arg);
        });
        ProcessResult result = await shell.run('wsl', args, runInShell: false);
        exitCode = result.exitCode;
        processes.add(exitCode);
      }
    }
    return processes;
  }

  /// Restart WSL
  Future<String> restart() async {
    ProcessResult results = await shell.run('wsl', ['--shutdown']);
    results = await shell.run('wsl', ['--shutdown']);
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
      results = await shell.run(
          'wsl', ['--import', distribution, installLocation, filename, '--vhd'],
          stdoutEncoding: null, stderrEncoding: null);
    } else {
      results = await shell.run(
          'wsl', ['--import', distribution, installLocation, filename],
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
    ProcessResult results = await shell.run(
        'wsl', ['--import', distribution, installPath, downloadPath],
        stdoutEncoding: null);

    return results;
  }

  var lastDistroList = Instances([], []);

  /// Returns list of WSL distros
  Future<Instances> list(bool showDocker) async {
    ProcessResult results =
        await shell.run('wsl', ['--list', '--quiet'], stdoutEncoding: null);
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

    try {
      // Step 1: Export the distribution
      String exportResult = await export(distribution, file);

      // Check if export was successful by verifying the file exists and has content
      File exportFile = File(file);
      if (!exportFile.existsSync()) {
        throw Exception('Export failed: Export file was not created at $file');
      }

      // Check if the export file has content (should be > 0 bytes)
      int fileSize = exportFile.lengthSync();
      if (fileSize == 0) {
        // Clean up empty file and throw error
        exportFile.deleteSync();
        throw Exception('Export failed: Export file is empty');
      }

      // Step 2: Remove the distribution only after successful export
      String removeResult = await remove(distribution);

      // Step 3: Import the distribution back
      String importResult = await import(distribution, instancePath.path, file);

      // Step 4: Clean up the temporary export file after successful import
      try {
        if (exportFile.existsSync()) {
          exportFile.deleteSync();
        }
      } catch (cleanupError) {
        // Log cleanup error but don't fail the overall operation
        logDebug('Failed to clean up export file: $cleanupError', null, null);
      }

      return 'Cleanup completed successfully: $exportResult $removeResult $importResult';
    } catch (error, stack) {
      // Log the error
      logError(error, stack, null);

      // If export file exists but cleanup failed, keep it for user recovery
      File exportFile = File(file);
      if (exportFile.existsSync()) {
        logDebug('Export file preserved at: $file', null, null);
      }

      // Re-throw the error to be handled by the caller
      throw Exception('Cleanup failed: ${error.toString()}');
    }
  }

  /// Returns list of WSL distros
  Future<List<String>> listRunning() async {
    ProcessResult results = await shell
        .run('wsl', ['--list', '--running', '--quiet'], stdoutEncoding: null);
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
    if (!exportFile.existsSync() || exportFile.lengthSync() == 0) {
      if (exportFile.existsSync()) {
        exportFile.deleteSync();
      }
      throw Exception("Export failed. Aborting move to prevent data loss.");
    }

    // Remove old
    await remove(distro);

    // Import new
    try {
      var res = await import(distro, newPath, exportFilePath);

      // Cleanup export file only if import succeeded
      await exportFile.delete();

      // Update preference
      prefs.setString('Path_$distro', newPath);

      return res;
    } catch (e) {
      throw Exception(
          "Import failed: $e. Your data is safe in: $exportFilePath. Please do not delete this file.");
    }
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
