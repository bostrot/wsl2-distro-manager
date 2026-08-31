import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wsl2distromanager/api/apple/apple_vm_api.dart';
import 'package:wsl2distromanager/api/shell.dart';
import 'package:wsl2distromanager/components/helpers.dart';

/// Scripted vmctl: answers by subcommand and records every invocation.
class FakeVmctlShell implements Shell {
  final List<List<String>> calls = [];
  final Map<String, String> responses = {};
  final Map<String, int> exitCodes = {};
  final Map<String, String> errors = {};

  String _commandOf(List<String> arguments) {
    // Skip the leading `--store <dir>`.
    var index = 0;
    while (index < arguments.length && arguments[index].startsWith('--')) {
      index += 2;
    }
    return index < arguments.length ? arguments[index] : '';
  }

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    Encoding? stdoutEncoding = systemEncoding,
    Encoding? stderrEncoding = systemEncoding,
  }) async {
    calls.add([executable, ...arguments]);
    final command = _commandOf(arguments);
    return ProcessResult(
      0,
      exitCodes[command] ?? 0,
      responses[command] ?? '',
      errors[command] ?? '',
    );
  }

  @override
  Future<Process> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    ProcessStartMode mode = ProcessStartMode.normal,
  }) async {
    calls.add(['start:$executable', ...arguments]);
    throw UnsupportedError('start is not scripted in this fake');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeVmctlShell shell;
  late AppleVmApi api;
  late Directory tempStore;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    shell = FakeVmctlShell();
    tempStore = Directory.systemTemp.createTempSync('applevm-test');
    api = AppleVmApi(
      shell: shell,
      helperPathOverride: '/fake/vmctl',
      storeDirOverride: tempStore.path,
      earlyExitProbeDelay: Duration.zero,
    );
  });

  tearDown(() {
    if (tempStore.existsSync()) tempStore.deleteSync(recursive: true);
  });

  List<String> lastCall() => shell.calls.last;

  group('identity', () {
    test('reports backend id, noun and template extension', () {
      expect(api.backendId, 'applevirt');
      expect(api.instanceNoun, 'VM');
      expect(api.templateExtension, 'img');
    });

    test('features exclude every WSL-only surface', () {
      final features = api.features;
      expect(features.wslConfig, isFalse);
      expect(features.packaging, isFalse);
      expect(features.mountDisk, isFalse);
      expect(features.aiWorkspace, isFalse);
      expect(features.quickActions, isFalse);
      expect(features.templatesDeprecated, isFalse);
      expect(features.createVm, isTrue);
    });
  });

  group('list', () {
    test('parses vmctl JSON into Instances', () async {
      shell.responses['list'] = json.encode({
        'vms': [
          {'name': 'ubuntu', 'state': 'running', 'os': 'linux', 'user': 'dev'},
          {'name': 'fedora', 'state': 'stopped', 'os': 'linux', 'user': 'user'},
        ]
      });
      final instances = await api.list(false);
      expect(instances.all, ['ubuntu', 'fedora']);
      expect(instances.running, ['ubuntu']);
      // The helper was invoked with the store and the json flag.
      expect(lastCall(), containsAll(['/fake/vmctl', '--store', 'list']));
    });

    test('empty store lists nothing', () async {
      shell.responses['list'] = '{"vms":[]}';
      final instances = await api.list(false);
      expect(instances.all, isEmpty);
      expect(instances.running, isEmpty);
    });

    test('unreadable output raises AppleVmException', () async {
      shell.responses['list'] = 'not json';
      expect(() => api.list(false), throwsA(isA<AppleVmException>()));
    });

    test('helper failure surfaces its stderr', () async {
      shell.exitCodes['list'] = 1;
      shell.errors['list'] = 'boom from vmctl';
      expect(
        () => api.list(false),
        throwsA(predicate((e) => e.toString().contains('boom from vmctl'))),
      );
    });
  });

  group('lifecycle', () {
    List<String> callWith(String verb) =>
        shell.calls.lastWhere((c) => c.contains(verb));

    test('start opens the VM with its display window', () async {
      shell.responses['start'] = '{"started":"ubuntu"}';
      shell.responses['list'] =
          '{"vms":[{"name":"ubuntu","state":"running"}]}';
      await api.start('ubuntu');
      expect(
          callWith('start'), containsAll(['start', '--name', 'ubuntu', '--gui']));
    });

    test('startHeadless omits the gui flag', () async {
      shell.responses['start'] = '{"started":"ubuntu"}';
      shell.responses['list'] =
          '{"vms":[{"name":"ubuntu","state":"running"}]}';
      await api.startHeadless('ubuntu');
      expect(callWith('start'), isNot(contains('--gui')));
    });

    test('a VM that stops right after starting is reported, with the '
        'serial log tail', () async {
      shell.responses['start'] = '{"started":"ubuntu"}';
      shell.responses['list'] =
          '{"vms":[{"name":"ubuntu","state":"stopped"}]}';
      Directory('${tempStore.path}/ubuntu/run').createSync(recursive: true);
      File('${tempStore.path}/ubuntu/run/serial.log')
          .writeAsStringSync('EFI: no bootable option');
      expect(
        () => api.start('ubuntu'),
        throwsA(predicate((e) =>
            e is AppleVmException &&
            e.message.contains('vmstoppedimmediately-text') &&
            e.message.contains('no bootable option'))),
      );
    });

    test('stop and remove hit the expected verbs', () async {
      shell.responses['stop'] = '{"stopped":"ubuntu"}';
      await api.stop('ubuntu');
      expect(lastCall(), containsAll(['stop', '--name', 'ubuntu']));

      shell.responses['delete'] = '{"deleted":"ubuntu"}';
      await api.remove('ubuntu');
      expect(lastCall(), containsAll(['delete', '--name', 'ubuntu']));
    });

    test('remove clears the per-instance preferences', () async {
      await prefs.setString('Path_gone', 'somewhere');
      await prefs.setString('DistroName_gone', 'Gone');
      shell.responses['delete'] = '{"deleted":"gone"}';
      await api.remove('gone');
      expect(prefs.getString('Path_gone'), isNull);
      expect(prefs.getString('DistroName_gone'), isNull);
    });

    test('shutdown stops every running VM', () async {
      shell.responses['list'] = json.encode({
        'vms': [
          {'name': 'a', 'state': 'running'},
          {'name': 'b', 'state': 'stopped'},
          {'name': 'c', 'state': 'running'},
        ]
      });
      shell.responses['stop'] = '{}';
      await api.shutdown();
      final stops = shell.calls.where((c) => c.contains('stop')).toList();
      expect(stops, hasLength(2));
      expect(stops[0], contains('a'));
      expect(stops[1], contains('c'));
    });
  });

  group('export / import / copy', () {
    test('export and import map to vmctl verbs', () async {
      shell.responses['export'] = '{}';
      await api.export('ubuntu', '/tmp/out.img');
      expect(lastCall(),
          containsAll(['export', '--name', 'ubuntu', '--output', '/tmp/out.img']));

      shell.responses['import'] = '{}';
      await api.import('clone', '', '/tmp/out.img');
      expect(lastCall(),
          containsAll(['import', '--name', 'clone', '--input', '/tmp/out.img']));
    });

    test('copy exports to a staging file, imports it and cleans up', () async {
      shell.responses['export'] = '{}';
      shell.responses['import'] = '{}';
      await api.copy('ubuntu', 'ubuntu2');
      final exportCall = shell.calls.firstWhere((c) => c.contains('export'));
      final importCall = shell.calls.firstWhere((c) => c.contains('import'));
      final staging = exportCall[exportCall.indexOf('--output') + 1];
      expect(staging, importCall[importCall.indexOf('--input') + 1]);
      expect(File(staging).existsSync(), isFalse);
    });
  });

  group('exec', () {
    test('execCommand hands the command over as ONE argument', () async {
      shell.responses['exec'] = 'hello';
      await api.execCommand('ubuntu', 'echo "a b" | wc -l');
      final call = lastCall();
      final separator = call.indexOf('--');
      // Everything after -- must be exactly one element: ssh flattens argv
      // with spaces and the guest shell re-parses it, the same trap wsl.exe
      // has.
      expect(call.sublist(separator + 1), ['echo "a b" | wc -l']);
    });

    test('cwd is prepended as a quoted cd', () async {
      shell.responses['exec'] = '';
      await api.execCommand('ubuntu', 'ls', cwd: "/tmp/it's here");
      final call = lastCall();
      expect(call.last, "cd '/tmp/it'\\''s here' && ls");
    });

    test('execCmdAsRoot runs as root and returns stdout', () async {
      shell.responses['exec'] = 'root-output';
      final out = await api.execCmdAsRoot('ubuntu', 'id');
      expect(out, 'root-output');
      expect(lastCall(), containsAll(['--user', 'root']));
    });
  });

  group('sizes and metadata', () {
    test('instanceSizeLabel reads the disk image on disk', () {
      final vmDir = Directory('${tempStore.path}/sized')..createSync();
      final disk = File('${vmDir.path}/disk.img');
      disk.writeAsBytesSync(List.filled(3 * 1024 * 1024, 0));
      // Too small for a GB label to show a whole number, but the format
      // stays the WSL one: "<n.nn> GB".
      expect(api.instanceSizeLabel('sized'), '0.00 GB');
      expect(api.instanceSizeLabel('missing'), '');
    });

    test('getDefaultUser comes from the VM config', () async {
      shell.responses['list'] = json.encode({
        'vms': [
          {'name': 'ubuntu', 'state': 'stopped', 'user': 'dev'},
        ]
      });
      expect(await api.getDefaultUser('ubuntu'), 'dev');
      expect(await api.getDefaultUser('missing'), 'root');
    });

    test('guestIp returns null when the helper has no lease', () async {
      shell.responses['ip'] = '{"ip":null}';
      expect(await api.guestIp('ubuntu'), isNull);
      shell.responses['ip'] = '{"ip":"192.168.64.5"}';
      expect(await api.guestIp('ubuntu'), '192.168.64.5');
    });
  });

  group('createLinuxVm / createMacosVm', () {
    test('linux create forwards sizes, user, iso and image', () async {
      shell.responses['create'] = '{"created":"dev"}';
      await api.createLinuxVm('dev',
          isoPath: '/tmp/ubuntu.iso',
          diskSizeGb: 64,
          cpus: 4,
          memoryGb: 8,
          user: 'eric');
      final call = lastCall();
      expect(
          call,
          containsAll([
            'create', '--name', 'dev', '--os', 'linux',
            '--disk-size', '64', '--cpus', '4', '--memory', '8',
            '--user', 'eric', '--iso', '/tmp/ubuntu.iso',
          ]));
      expect(call, isNot(contains('--image')));
    });

    test('macos create forwards the restore image', () async {
      shell.responses['create'] = '{"created":"sequoia"}';
      await api.createMacosVm('sequoia', restoreImagePath: '/tmp/r.ipsw');
      expect(
          lastCall(),
          containsAll([
            'create', '--name', 'sequoia', '--os', 'macos',
            '--restore-image', '/tmp/r.ipsw',
          ]));
    });
  });
}
