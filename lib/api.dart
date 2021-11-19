import 'dart:io';
import 'dart:convert' show utf8, json;
import 'package:dio/dio.dart';
// import 'package:package_info_plus/package_info_plus.dart';

const String updateUrl =
    'https://api.github.com/repos/bostrot/wsl2-distro-manager/releases';

const String motdUrl =
    'https://raw.githubusercontent.com/bostrot/wsl2-distro-manager/main/motd.json';

class Instances {
  List<String> running = [];
  List<String> all = [];
  Instances(this.all, this.running);
}

class App {
  /// Returns an int of the string
  double versionToDouble(String version) {
    return double.tryParse(version
            .toString()
            .replaceAll('v', '')
            .replaceAll('.', '')
            .replaceAll('+', '.')) ??
        -1;
  }

  /// Returns an url as String when the app is not up-to-date otherwise empty string
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

class WSLApi {
  WSLApi() {
    mkRootDir();
  }

  // Create directory
  void mkRootDir() async {
    //await Process.run('help', []);
    await Process.start('cmd.exe', ['/c', 'mkdir', 'C:\\WSL2-Distros\\']);
  }

  // Install WSL
  void installWSL() async {
    Process.start(
        'powershell',
        [
          'Start-Process cmd -ArgumentList "/c wsl --install" -Verb RunAs',
        ],
        mode: ProcessStartMode.detached,
        runInShell: true);
  }

  // Start a WSL distro by name
  void start(String distribution) async {
    Process.start('start', ['wsl', '-d', distribution],
        mode: ProcessStartMode.detached, runInShell: true);
  }

  // Stop a WSL distro by name
  Future<String> stop(String distribution) async {
    ProcessResult results =
        await Process.run('wsl', ['--terminate', distribution]);
    return results.stdout;
  }

  // Start VSCode
  void startVSCode(String distribution) async {
    Process.start('start', ['wsl', '-d', distribution, 'code'],
        mode: ProcessStartMode.normal, runInShell: true);
  }

  // Start Explorer
  void startExplorer(String distribution) async {
    Process.start('start', ['explorer.exe', '\\\\wsl.localhost\\$distribution'],
        mode: ProcessStartMode.normal, runInShell: true);
  }

  // Start a WSL distro by name
  Future<String> copy(String distribution, String newName,
      {String location = 'C:\\WSL2-Distros\\'}) async {
    if (location == '') {
      location = 'C:\\WSL2-Distros\\';
    }
    String exportRes =
        await export(distribution, location + distribution + '.tar');
    String importRes = await import(
        newName, location + newName, location + distribution + '.tar');
    return exportRes + ' ' + importRes;
  }

  // Export a WSL distro by name
  Future<String> export(String distribution, String location) async {
    ProcessResult results =
        await Process.run('wsl', ['--export', distribution, location]);
    return results.stdout;
  }

  // Remove a WSL distro by name
  Future<String> remove(String distribution) async {
    ProcessResult results =
        await Process.run('wsl', ['--unregister', distribution]);
    return results.stdout;
  }

  // Install a WSL distro by name
  Future<String> install(String distribution) async {
    ProcessResult results =
        await Process.run('wsl', ['--install', '-d', distribution]);
    return results.stdout;
  }

  // Import a WSL distro by name
  Future<String> import(
      String distribution, String installLocation, String location) async {
    ProcessResult results = await Process.run(
        'wsl', ['--import', distribution, installLocation, location]);
    return results.stdout;
  }

  // Returns list of WSL distros
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

  // Returns list of WSL distros
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

  // Returns list of downloadable WSL distros
  Future<List<String>> getDownloadable() async {
    ProcessResult results =
        await Process.run('wsl', ['--list', '--online'], stdoutEncoding: null);
    String output = utf8Convert(results.stdout);
    List<String> list = [];
    bool nameStarted = false;
    output.split('\n').forEach((line) {
      // Filter out docker data
      if (line != '' && nameStarted) {
        list.add(line.split(' ')[0]);
      }
      // List started
      if (line.startsWith('NAME')) {
        nameStarted = true;
      }
    });
    return list;
  }

  // Convert bytes to human readable string while removing non-ascii characters
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
