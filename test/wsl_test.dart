/// Tests for the wsl.dart file.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wsl2distromanager/api/app.dart';
import 'package:wsl2distromanager/api/shell.dart';
import 'package:wsl2distromanager/api/wsl.dart';
import 'package:wsl2distromanager/components/constants.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/components/notify.dart';
import 'package:wsl2distromanager/dialogs/create_dialog.dart';

class MockHttpClientAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    if (options.path.contains('releases')) {
      return ResponseBody.fromString(
          jsonEncode([
            {
              'tag_name': 'v2.0.0',
              'published_at': DateTime.now()
                  .subtract(const Duration(days: 3))
                  .toIso8601String(),
              'html_url': 'https://github.com/example/release.msix'
            }
          ]),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType]
          });
    }
    if (options.path.contains('motd')) {
      return ResponseBody.fromString(jsonEncode({'motd': 'Hello Test'}), 200,
          headers: {
            Headers.contentTypeHeader: [Headers.textPlainContentType]
          });
    }
    if (options.path.contains('images.json')) {
      return ResponseBody.fromString(
          jsonEncode({'Debian': 'http://example.com/debian.tar.gz'}), 200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType]
          });
    }
    return ResponseBody.fromString('', 404);
  }

  @override
  void close({bool force = false}) {}
}

class MockShell implements Shell {
  final List<String> distros = [];

  // Flags to simulate error conditions in tests
  bool simulateExportFailure = false;
  bool simulatePermissionDenied = false;
  bool simulateInvalidPath = false;

  @override
  Future<ProcessResult> run(String executable, List<String> arguments,
      {String? workingDirectory,
      Map<String, String>? environment,
      bool includeParentEnvironment = true,
      bool runInShell = false,
      Encoding? stdoutEncoding = systemEncoding,
      Encoding? stderrEncoding = systemEncoding}) async {
    String stdout = '';
    String stderr = '';
    int exitCode = 0;

    if (arguments.contains('--list')) {
      stdout = distros.join('\n');
    }

    if (arguments.contains('--export')) {
      String location = arguments[2];
      // Simulate permission denied
      if (simulatePermissionDenied) {
        stderr = 'Permission denied';
        exitCode = 1;
      } else if (simulateExportFailure) {
        // Generic export failure
        stderr = 'Export failed';
        exitCode = 2;
      } else {
        File(location).createSync(recursive: true);
        File(location).writeAsStringSync('dummy content');
      }
    }

    if (arguments.contains('--import')) {
      String distro = arguments[1];
      String installLocation = arguments[2];
      // Simulate invalid path
      if (simulateInvalidPath) {
        stderr = 'Invalid installation path: $installLocation';
        exitCode = 3;
      } else if (simulatePermissionDenied) {
        stderr = 'Permission denied';
        exitCode = 1;
      } else {
        if (!distros.contains(distro)) {
          distros.add(distro);
        }
        File('$installLocation/ext4.vhdx').createSync(recursive: true);
      }
    }

    if (arguments.contains('--unregister')) {
      String distro = arguments[1];
      distros.remove(distro);
    }

    if (arguments.contains('--install')) {
      if (arguments.contains('-d')) {
        String distro = arguments[arguments.indexOf('-d') + 1];
        distros.add(distro);
      }
    }

    dynamic stdoutData = stdout;
    if (stdoutEncoding == null) {
      stdoutData = utf8.encode(stdout);
    }

    dynamic stderrData = stderr;
    if (stderrEncoding == null) {
      stderrData = utf8.encode(stderr);
    }

    return ProcessResult(0, exitCode, stdoutData, stderrData);
  }

  @override
  Future<Process> start(String executable, List<String> arguments,
      {String? workingDirectory,
      Map<String, String>? environment,
      bool includeParentEnvironment = true,
      bool runInShell = false,
      ProcessStartMode mode = ProcessStartMode.normal}) async {
    // Return a dummy process
    return MockProcess();
  }
}

class MockProcess implements Process {
  @override
  Future<int> get exitCode => Future.value(0);

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;

  @override
  int get pid => 1;

  @override
  Stream<List<int>> get stderr => Stream.empty();

  @override
  IOSink get stdin => IOSink(StreamController<List<int>>().sink);

  @override
  Stream<List<int>> get stdout => Stream.empty();
}

void main() {
  late MockShell mockShell;
  late WSLApi wslApi;
  late Dio mockDio;

  void statusMsg(
    String msg, {
    Duration? duration,
    dynamic severity = "",
    bool loading = false,
    bool useWidget = false,
    bool leadingIcon = true,
    dynamic widget,
  }) {}

  // Stuff before tests
  setUpAll(() async {
    // Init bindings for tests
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    // Init prefs
    await initPrefs();

    Notify();
    Notify.message = statusMsg;
  });

  setUp(() {
    mockShell = MockShell();
    wslApi = WSLApi(shell: mockShell);
    mockDio = Dio();
    mockDio.httpClientAdapter = MockHttpClientAdapter();
  });

  test('Check update', () async {
    App app = App(dio: mockDio);
    var updateUrl = await app.checkUpdate('1.0.0');
    // Check if updateUrl contains https:// and .msix
    expect(updateUrl.contains('https://'), true);
    expect(updateUrl.contains('.msix'), true);
  });

  test('Version to double', () {
    App app = App();
    var version = app.versionToDouble('1.0.0');
    expect(version, 100.0);
  });

  test('Check motd', () async {
    App app = App(dio: mockDio);
    var motd = await app.checkMotd();
    expect(motd, isNotEmpty);
  });

  test('Get distro links', () async {
    App app = App(dio: mockDio);
    var links = await app.getDistroLinks();
    expect(links, isNotEmpty);
  });

  test('UTF16 to UTF8', () {
    // Create a UTF16 string
    var utf16 = 'Hello World';
    // To bytes
    var bytes = utf16.codeUnits;
    // Add 0 between each byte
    var bytes2 = bytes.expand((e) => [e, 0]).toList();

    // Convert to UTF8
    var utf8 = wslApi.utf8Convert(bytes2);
    expect(utf8, utf16);
  });

  Future<bool> isInstance(String name) async {
    bool found;
    // Get list
    var list = await wslApi.list(false);
    found = false;

    for (var item in list.all) {
      if (item == name) {
        found = true;
      }
    }
    return found;
  }

  createDistro(name, loc, image, user) async {
    await createInstance(
      TextEditingController(text: name),
      TextEditingController(text: loc),
      wslApi,
      TextEditingController(text: image),
      TextEditingController(text: user),
    );
  }

  test('Create instance test', () async {
    // Save original state of distroRootfsLinks and restore after test to prevent test pollution
    final originalDistroRootfsLinks =
        Map<String, String>.from(distroRootfsLinks);
    addTearDown(() {
      distroRootfsLinks
        ..clear()
        ..addAll(originalDistroRootfsLinks);
    });
    // Test with download
    distroRootfsLinks['Debian'] = 'http://example.com/debian.tar.gz';

    final file = File('C:/WSL2-Distros/distros/Debian.tar.gz');
    if (!await file.exists()) {
      file.createSync(recursive: true);
    }

    // Delete the instance
    await wslApi.remove('test');
    expect(await isInstance('test'), false);

    // Test creating it
    await createDistro(
      'test',
      '',
      'Debian',
      '',
    );

    // Verify that the file exists
    expect(await file.exists(), true);
    expect(await isInstance('test'), true);

    // Delete the instance
    await wslApi.remove('test');
    expect(await isInstance('test'), false);

    // Test without download
    // Test creating it
    await createDistro(
      'test',
      '',
      'Debian',
      '',
    );

    expect(await isInstance('test'), true);
  });

  test('Copy instance test', () async {
    // Setup: create 'test'
    mockShell.distros.add('test');
    File('C:/WSL2-Distros/test/ext4.vhdx').createSync(recursive: true);

    // Old copy
    await wslApi.copy('test', 'testcopy');
    expect(await isInstance('testcopy'), true);

    // New copy with vhd
    await wslApi.stop('test');
    await wslApi.copyVhd('test', 'testcopy2');

    expect(await isInstance('testcopy2'), true);

    // Delete the instance
    await wslApi.remove('test');
    await wslApi.remove('testcopy');
    await wslApi.remove('testcopy2');

    expect(await isInstance('test'), false);
    expect(await isInstance('testcopy'), false);
    expect(await isInstance('testcopy2'), false);
  });

  test('Cleanup test', () async {
    // Create a new instance
    mockShell.distros.add('test');
    File('C:/WSL2-Distros/test/ext4.vhdx').createSync(recursive: true);

    // Cleanup
    String result = await wslApi.cleanup('test');

    // Should return success message
    expect(result, contains('Cleanup completed successfully'));

    // Still exists (cleanup re-imports it)
    expect(await isInstance('test'), true);

    // Check that export file is cleaned up (should not exist after successful cleanup)
    var exportFile = File('C:/WSL2-Distros/test/export.tar.gz');
    expect(await exportFile.exists(), false);
  });

  test('Cleanup test with nonexistent instance', () async {
    // Try to cleanup a nonexistent instance
    const name = 'nonexistent-instance';

    try {
      var result = await wslApi.cleanup(name);

      // If cleanup returns a result, it should indicate the instance wasn't found or an error occurred.
      // We accept several possible error phrases to be robust against implementation differences.
      final lower = result.toLowerCase();
      final handled = lower.contains('not found') ||
          lower.contains('does not exist') ||
          lower.contains('no such') ||
          lower.contains('error') ||
          lower.contains('not exist');

      expect(handled, true,
          reason:
              'cleanup returned a message but it did not indicate a missing instance or an error: "$result"');
    } catch (e) {
      // If it throws, ensure it's some form of Exception/Error.
      expect(e, isA<Exception>());
    }
  });

  test('Move distro', () async {
    // Create a new instance
    mockShell.distros.add('test');
    File('C:/WSL2-Distros/test/ext4.vhdx').createSync(recursive: true);

    // Move it
    await wslApi.move('test', 'C:/WSL2-Distros/test-moved');

    // File exists
    var file = File('C:/WSL2-Distros/test-moved/ext4.vhdx');
    expect(await file.exists(), true);

    // Still exists
    expect(await isInstance('test'), true);

    // Delete the instance
    await wslApi.remove('test');
    expect(await isInstance('test'), false);

    // Delete folder
    if (await Directory('C:/WSL2-Distros/test-moved').exists()) {
      await Directory('C:/WSL2-Distros/test-moved').delete(recursive: true);
    }
  });
}
