import 'dart:convert';
import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart' show InfoBarSeverity;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wsl2distromanager/api/apple/apple_vm_api.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/components/notify.dart';

import 'fake_vmctl_shell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    Notify();
    Notify.message = (msg,
        {duration,
        severity = InfoBarSeverity.info,
        loading = false,
        useWidget = false,
        leadingIcon = true,
        dynamic widget}) {};
  });

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
      expect(features.templatesDeprecated, isFalse);
      expect(features.createVm, isTrue);
      // The AI Workspace (a dedicated Linux VM), the serial console and
      // snippets are all supported on this backend, unlike the WSL-only
      // families above.
      expect(features.aiWorkspace, isTrue);
      expect(features.serialConsole, isTrue);
      expect(features.quickActions, isTrue);
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

  // A VM installed by hand from an ISO never got the store key from
  // cloud-init, so `exec` — and every snippet — failed with ssh's
  // "Permission denied" in a Terminal window (bostrot/ai-tasks#16).
  group('guest access', () {
    test('probe is ok when `true` runs by key', () async {
      final probe = await api.probeGuestAccess('alpine_2');
      expect(probe.ok, isTrue);
      expect(lastCall(), containsAll(['exec', '--user', 'root', 'true']));
    });

    test('probe tells a missing key apart from any other failure', () async {
      shell.exitCodes['exec'] = 255;
      shell.errors['exec'] =
          'root@192.168.64.2: Permission denied (publickey,password,keyboard-interactive).';
      final denied = await api.probeGuestAccess('alpine_2', user: 'root');
      expect(denied.state, GuestAccessState.denied);
      expect(denied.message, contains('Permission denied'));

      // ssh's 255 for anything else (no route, no sshd) is not repairable
      // with a password, and must not open the credentials dialog.
      shell.errors['exec'] = 'ssh: connect to host 192.168.64.2 port 22: Connection refused';
      final refused = await api.probeGuestAccess('alpine_2');
      expect(refused.state, GuestAccessState.unreachable);
      expect(refused.message, contains('Connection refused'));

      // A stopped VM: vmctl itself says so with exit 1.
      shell.exitCodes['exec'] = 1;
      shell.errors['exec'] = 'VM alpine_2 is not running.';
      final stopped = await api.probeGuestAccess('alpine_2');
      expect(stopped.state, GuestAccessState.unreachable);
      expect(stopped.message, 'VM alpine_2 is not running.');
    });

    test('authorizeSshKey passes the password by environment, never argv',
        () async {
      shell.responses['authorize'] =
          '{"authorized":"alpine_2","root":true,"user":"eric"}';
      final result = await api.authorizeSshKey('alpine_2',
          user: 'eric', password: 'p4ss w0rd');
      expect(result.user, 'eric');
      expect(result.rootInstalled, isTrue);
      final call = lastCall();
      expect(call, containsAll(['authorize', '--name', 'alpine_2', '--user', 'eric']));
      expect(call.join(' '), isNot(contains('p4ss')));
      expect(shell.environments.last, {AppleVmApi.guestPasswordEnv: 'p4ss w0rd'});
    });

    test('authorizeSshKey reports when only the login user got the key',
        () async {
      shell.responses['authorize'] =
          '{"authorized":"alpine_2","root":false,"user":"eric"}';
      final result = await api.authorizeSshKey('alpine_2',
          user: 'eric', password: 'x');
      expect(result.rootInstalled, isFalse);
    });

    test('authorizeSshKey surfaces ssh\'s reason on a failed sign-in',
        () async {
      shell.exitCodes['authorize'] = 1;
      shell.errors['authorize'] =
          'Could not sign in as eric@192.168.64.2: Permission denied (publickey,password).';
      expect(
          () => api.authorizeSshKey('alpine_2', user: 'eric', password: 'x'),
          throwsA(isA<AppleVmException>().having((e) => e.message, 'message',
              contains('Could not sign in as eric'))));
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

  group('helper discovery', () {
    test('a dev environment resolves a real vmctl, never the bare name',
        () {
      // No override: exercise the real candidate chain. In a checkout (this
      // test run) the repo build output or the installed dev copy must win
      // over falling through to PATH.
      final discovered = AppleVmApi(shell: shell).helperPath();
      expect(discovered, isNot('vmctl'),
          reason: 'debug runs must find a concrete helper binary');
      expect(File(discovered).existsSync(), isTrue);
    });
  });

  group('startExplorer / disk mounting', () {
    test('a stopped VM with a mountable partition opens the volume',
        () async {
      shell.responses['list'] =
          '{"vms":[{"name":"ubuntu","state":"stopped"}]}';
      shell.responses['attach'] = '/dev/disk4              \n'
          '/dev/disk4s1        EFI        /Volumes/EFI BOOT\n';
      api.startExplorer('ubuntu');
      await Future<void>.delayed(Duration.zero);
      final opened =
          shell.calls.where((c) => c.first == 'start:open').toList();
      expect(opened, isNotEmpty);
      expect(opened.first.last, '/Volumes/EFI BOOT');
    });

    test('an unmountable disk detaches again and opens the VM folder',
        () async {
      shell.responses['list'] =
          '{"vms":[{"name":"ubuntu","state":"stopped"}]}';
      // Attached, but macOS mounted no volume (ext4-only disk).
      shell.responses['attach'] = '/dev/disk4\n';
      api.startExplorer('ubuntu');
      await Future<void>.delayed(Duration.zero);
      expect(shell.calls.any((c) => c.contains('detach')), isTrue,
          reason: 'a device nothing mounted must not stay attached');
      final opened = shell.calls.lastWhere((c) => c.first == 'start:open');
      expect(opened.last, contains('ubuntu'));
    });

    test('a running VM never attaches its disk', () async {
      shell.responses['list'] =
          '{"vms":[{"name":"ubuntu","state":"running"}]}';
      api.startExplorer('ubuntu');
      await Future<void>.delayed(Duration.zero);
      expect(shell.calls.any((c) => c.contains('attach')), isFalse);
      expect(shell.calls.any((c) => c.first == 'start:open'), isTrue);
    });

    test('start refuses while the disk is mounted in Finder', () async {
      shell.responses['info'] =
          'image-path : ${tempStore.path}/ubuntu/disk.img\n';
      await expectLater(
          api.start('ubuntu'),
          throwsA(predicate(
              (e) => e.toString().contains('vmejectbeforestart-text'))));
      expect(shell.calls.any((c) => c.contains('start') && c.length > 2),
          isFalse, reason: 'the guard must fire before vmctl start');
    });
  });

  group('row labels', () {
    test('the row shows real usage next to the allocation, and the IP',
        () async {
      final vmDir = Directory('${tempStore.path}/ubuntu')..createSync(recursive: true);
      // 32 MiB logical (sparse allocation stand-in for the test).
      final disk = File('${vmDir.path}/disk.img');
      disk.writeAsBytesSync(List.filled(32 * 1024 * 1024, 0));
      // du says 1.5 GiB of real blocks (value in KiB).
      shell.responses['-k'] = '1572864\t${disk.path}';
      shell.responses['list'] = json.encode({
        'vms': [
          {'name': 'ubuntu', 'state': 'running', 'ip': '192.168.64.7'},
        ]
      });

      await api.list(false); // caches the IP
      // First call kicks the du probe and shows the allocation alone.
      expect(api.instanceMetaLabel('ubuntu'), '192.168.64.7 · 0.03 GB');
      await Future<void>.delayed(Duration.zero);
      expect(api.instanceMetaLabel('ubuntu'), '192.168.64.7 · 1.50 GB / 0.03 GB');
    });

    test('a stopped VM shows no IP', () async {
      final vmDir = Directory('${tempStore.path}/quiet')..createSync(recursive: true);
      File('${vmDir.path}/disk.img')
          .writeAsBytesSync(List.filled(1024 * 1024, 0));
      shell.responses['list'] = json.encode({
        'vms': [
          {'name': 'quiet', 'state': 'stopped', 'ip': '192.168.64.9'},
        ]
      });
      await api.list(false);
      expect(api.instanceMetaLabel('quiet'), isNot(contains('192.168')));
    });
  });

  group('runCommands', () {
    test('opens a Terminal .command that execs the snippet via vmctl',
        () async {
      api.runCommands('ubuntu', ['echo hi', 'ls -la'], user: 'dev');
      await Future<void>.delayed(Duration.zero);
      final openCall = shell.calls.lastWhere((c) => c.first == 'start:open');
      final scriptPath = openCall.last;
      expect(scriptPath, endsWith('snippet.command'));
      final script = File(scriptPath).readAsStringSync();
      expect(script, contains('exec'));
      expect(script, contains('--name "ubuntu"'));
      expect(script, contains('--user "dev"'));
      // The snippet travels base64-encoded, decoded in the guest.
      expect(script, contains('base64 -d | sh'));
    });
  });

  group('showDisplay', () {
    test('asks the daemon to present the screen', () async {
      shell.responses['show'] = '{"shown":"ubuntu"}';
      await api.showDisplay('ubuntu');
      expect(lastCall(), containsAll(['show', '--name', 'ubuntu']));
    });

    test('a stopped VM surfaces the helper error', () async {
      shell.exitCodes['show'] = 1;
      shell.errors['show'] = 'VM ubuntu is not running.';
      expect(
          () => api.showDisplay('ubuntu'),
          throwsA(predicate(
              (e) => e.toString().contains('is not running'))));
    });
  });

  group('openConsole', () {
    test('a stopped VM is started headless first', () async {
      shell.responses['start'] = '{"started":"ubuntu"}';
      // The canned list keeps answering "stopped", so the early-exit probe
      // throws after the start — which is fine here: the claim under test
      // is that console mode starts the VM *without* a display window.
      shell.responses['list'] =
          '{"vms":[{"name":"ubuntu","state":"stopped"}]}';
      await expectLater(api.openConsole('ubuntu'), throwsA(anything));
      final startCall = shell.calls
          .firstWhere((c) => c.contains('start') && c.first != 'start:open');
      expect(startCall, isNot(contains('--gui')),
          reason: 'console mode must not open a display window');
    });

    test('writes a runnable .command bridge and opens it in Terminal',
        () async {
      shell.responses['list'] =
          '{"vms":[{"name":"ubuntu","state":"running"}]}';
      await api.openConsole('ubuntu');

      // Running already: no start was issued.
      expect(shell.calls.where((c) => c.contains('start') && c.length > 2),
          isEmpty);
      final openCall =
          shell.calls.lastWhere((c) => c.first == 'start:open');
      final scriptPath = openCall.last;
      expect(scriptPath, endsWith('console.command'));
      final script = File(scriptPath).readAsStringSync();
      expect(script, contains('/fake/vmctl'));
      expect(script, contains('console'));
      expect(script, contains('--name "ubuntu"'));
      expect(script, contains(tempStore.path));
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
