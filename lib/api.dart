import 'dart:io';
import 'dart:convert' show utf8;

class WSLApi {
  WSLApi() {
    mkRootDir();
  }

  // Create directory
  void mkRootDir() async {
    //await Process.run('help', []);
    await Process.start('cmd.exe', ['/c', 'mkdir', 'C:\\WSL2-Distros\\']);
  }

  // Start a WSL distro by name
  void start(String distribution) async {
    Process.start('start', ['wsl', '-d', distribution],
        mode: ProcessStartMode.detached, runInShell: true);
  }

  // Start a WSL distro by name
  Future<String> copy(String distribution, String newName,
      {String location = 'C:\\WSL2-Distros\\'}) async {
    if (location == '') {
      location = 'C:\\WSL2-Distros\\';
    }
    print("$distribution, $location + $distribution + '.tar'");
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
  Future<List<String>> list() async {
    ProcessResult results =
        await Process.run('wsl', ['--list', '--quiet'], stdoutEncoding: null);
    String output = utf8Convert(results.stdout);
    List<String> list = [];
    output.split('\n').forEach((line) {
      // Filter out docker data
      if (line != '' &&
          !line.startsWith('docker-desktop-data') &&
          !line.startsWith('docker-desktop')) {
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
