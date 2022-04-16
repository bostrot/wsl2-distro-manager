import 'dart:async';
import 'dart:io';
import 'dart:convert' show Utf8Decoder, json, utf8;
import 'package:dio/dio.dart';
import 'constants.dart';
import 'helpers.dart';
// import 'package:package_info_plus/package_info_plus.dart';

class Instances {
  List<String> running = [];
  List<String> all = [];
  Instances(this.all, this.running);
}

class App {
  /// Returns an int of the string
  /// '1.2.3' -> 123
  /// @param versionString: String
  /// @return double
  double versionToDouble(String version) {
    return double.tryParse(version
            .toString()
            .replaceAll('v', '')
            .replaceAll('.', '')
            .replaceAll('+', '.')) ??
        -1;
  }

  /// Returns an url as String when the app is not up-to-date otherwise empty string
  /// @param version: String
  /// @return Future<String>
  Future<String> checkUpdate(String version) async {
    try {
      var response = await Dio().get(updateUrl);
      if (response.data.length > 0) {
        var latest = response.data[0];
        String tagName = latest['tag_name'];

        // TODO: change version to PackageInfo once it works with Windows
        /* PackageInfo packageInfo = await PackageInfo.fromPlatform();
        String version = packageInfo.buildNumber; */
        if (versionToDouble(tagName) > versionToDouble(version)) {
          return latest['assets'][0]['browser_download_url'];
        }
      }
    } catch (e) {
      // ignored
    }
    return '';
  }

  /// Returns the message of the day
  /// @return Future<String>
  Future<String> checkMotd() async {
    try {
      var response = await Dio().get(motdUrl);
      if (response.data.length > 0) {
        var jsonData = json.decode(response.data);
        String motd = jsonData['motd'];
        return motd;
      }
    } catch (e) {
      // ignored
    }
    return '';
  }
}

/// WSL API
class WSLApi {
  /// Create directory
  void mkRootDir() async {
    //await Process.run('help', []);
    await Process.start('cmd.exe', ['/c', 'mkdir', defaultPath]);
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
  /// @param distribution: String
  /// @param startPath: String (optional) Defaults to root ('/')
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
    }
    Process.start('start', args,
        mode: ProcessStartMode.detached, runInShell: true);
  }

  /// Stop a WSL distro by name
  /// @param distribution: String
  /// @return Future<String>
  Future<String> stop(String distribution) async {
    ProcessResult results =
        await Process.run('wsl', ['--terminate', distribution]);
    return results.stdout;
  }

  /// Open bashrc with notepad from WSL
  /// @param distribution: String
  Future<String> openBashrc(String distribution) async {
    List<String> argsRc = ['wsl', '-d', distribution, 'notepad.exe', '.bashrc'];
    Process results = await Process.start('start', argsRc,
        mode: ProcessStartMode.normal, runInShell: true);
    return results.stdout.toString();
  }

  /// Shutdown WSL
  /// @return Future<String>
  Future<String> shutdown() async {
    ProcessResult results = await Process.run('wsl', ['--shutdown']);
    return results.stdout;
  }

  /// Start VSCode
  /// @param distribution: String
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
    File file =
        File('C:\\Users\\${Platform.environment['USERNAME']}\\.wslconfig');
    if (!file.existsSync()) {
      file.createSync();
    }
    file.writeAsStringSync('[wsl2]\n\n$text');
  }

  /// Read wslconfig file
  /// @return Future<Map<String, String>>
  Future<Map<String, String>> readConfig() async {
    File file =
        File('C:\\Users\\${Platform.environment['USERNAME']}\\.wslconfig');
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
    Process.start('start', ['notepad.exe', '%USERPROFILE%\\.wslconfig'],
        mode: ProcessStartMode.normal, runInShell: true);
  }

  /// Open distro config file
  void editDistroConfig(String distroname) async {
    String path =
        prefs.getString("Path_$distroname") ?? defaultPath + distroname;
    Process.start('start', ['notepad.exe', '$path\\startup.sh'],
        mode: ProcessStartMode.normal, runInShell: true);
  }

  /// Start Explorer
  /// @param distribution: String
  void startExplorer(String distribution, {String path = ''}) async {
    String fullPath = '\\\\wsl.localhost\\$distribution';
    if (path != '') {
      path = path.replaceAll('/', '\\');
      fullPath += path;
    }
    Process.start('start', ['explorer.exe', fullPath],
        mode: ProcessStartMode.normal, runInShell: true);
  }

  /// Copy a WSL distro by name
  /// @param distribution: String
  /// @param newName: String
  /// @param location: String (optional)
  /// @return Future<String>
  Future<String> copy(String distribution, String newName,
      {String location = defaultPath}) async {
    if (location == '') {
      location = defaultPath;
    }
    String exportRes =
        await export(distribution, location + distribution + '.tar');
    String importRes = await import(
        newName, location + newName, location + distribution + '.tar');
    return exportRes + ' ' + importRes;
  }

  /// Export a WSL distro by name
  /// @param distribution: String
  /// @param location: String
  /// @return Future<String>
  Future<String> export(String distribution, String location) async {
    ProcessResult results =
        await Process.run('wsl', ['--export', distribution, location]);
    return results.stdout;
  }

  /// Remove a WSL distro by name
  /// @param distribution: String
  /// @return Future<String>
  Future<String> remove(String distribution) async {
    ProcessResult results =
        await Process.run('wsl', ['--unregister', distribution]);
    return results.stdout;
  }

  /// Install a WSL distro by name
  /// @param distribution: String
  /// @return Future<String>
  Future<String> install(String distribution) async {
    ProcessResult results =
        await Process.run('wsl', ['--install', '-d', distribution]);
    return results.stdout;
  }

  List<String> resultQueue = [];

  /// Get the current cached output
  /// @return String
  String getCurrentOutput() {
    String tmp = resultQueue.join('\n');
    resultQueue = [];
    return tmp;
  }

  /// Executes a command list in a WSL distro
  /// @param distribution: String
  /// @param cmd: List<String>
  /// @return Future<List<int>>
  Future<List<int>> execCmds(
    String distribution,
    List<String> cmds, {
    required Function(String) onMsg,
    required Function onDone,
  }) async {
    List<int> processes = [];
    Process result = await Process.start(
        'wsl', ['-d', distribution, '-u', 'root'],
        mode: ProcessStartMode.detachedWithStdio);

    Timer currentWaiter = Timer(const Duration(seconds: 15), () {
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

    for (var cmd in cmds) {
      result.stdin.writeln(cmd);
    }
    return processes;
  }

  /// Executes a command in a WSL distro and returns the output
  /// @param distribution: String
  /// @param cmd: String
  /// @return Future<String>
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
  /// @param distribution: String
  /// @param cmd: List<String>
  /// @return Future<List<int>>
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
  /// @return Future<String>
  Future<String> restart() async {
    ProcessResult results = await Process.run('wsl', ['--shutdown']);
    results = await Process.run('wsl', ['--shutdown']);
    return results.stdout;
  }

  /// Import a WSL distro by name
  /// @param distribution: String
  /// @param installLocation: String
  /// @param filename: String
  /// @return Future<String>
  Future<String> import(
      String distribution, String installLocation, String filename) async {
    if (installLocation == '') {
      installLocation = defaultPath + '/' + distribution;
    }
    ProcessResult results = await Process.run(
        'wsl', ['--import', distribution, installLocation, filename]);
    return results.stdout;
  }

  /// Import a WSL distro by name
  /// @param distribution: String
  /// @param installPath: String distro name or tar file
  /// @param filename: String
  /// @return Future<String>
  Future<dynamic> create(String distribution, String filename,
      String installPath, Function(String) status) async {
    if (installPath == '') {
      installPath = defaultPath + distribution;
    }

    // Download
    String downloadPath = '';
    downloadPath = defaultPath + 'distros\\' + filename + '.tar.gz';
    if (distroRootfsLinks[filename] != null &&
        !(await File(downloadPath).exists())) {
      String url = distroRootfsLinks[filename]!;
      // Download file
      try {
        Dio dio = Dio();
        await dio.download(url, downloadPath,
            onReceiveProgress: (int count, int total) {
          status('Step 1: Downloading distro: '
              '${(count / total * 100).toStringAsFixed(0)}%');
        });
      } catch (error) {
        status('Error downloading: $error');
      }
    }

    // Downloaded or extracted
    if (distroRootfsLinks[filename] == null) {
      downloadPath = filename;
    }

    // Create
    ProcessResult results = await Process.run(
        'wsl', ['--import', distribution, installPath, downloadPath]);
    return results;
  }

  /// Returns list of WSL distros
  /// @return Future<Instances>
  Future<Instances> list() async {
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
      output.split('\n').forEach((line) {
        // Filter out docker data
        if (line != '' &&
            !line.startsWith('docker-desktop-data') &&
            !line.startsWith('docker-desktop')) {
          list.add(line);
        }
      });
      List<String> running = await listRunning();
      return Instances(list, running);
    } else {
      return Instances(['wslNotInstalled'], []);
    }
  }

  /// Returns list of WSL distros
  /// @return Future<List<String>>
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
  /// @return Future<List<String>>
  Future<List<String>> getDownloadable(
      String repo, Function(String) onError) async {
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

  /// Convert bytes to human readable string while removing non-ascii characters
  /// @param bytes: List<int>
  /// @return String
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
}
