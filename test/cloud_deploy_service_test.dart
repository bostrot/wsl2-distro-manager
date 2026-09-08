import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wsl2distromanager/api/cloud/cloud_deploy_service.dart';
import 'package:wsl2distromanager/api/cloud/cloud_models.dart';
import 'package:wsl2distromanager/components/helpers.dart';

import 'fake_cloud.dart';

/// What `ssh-keygen -l` prints for the key the fake ~/.ssh holds.
const String _md5Line = '256 MD5:aa:bb:cc wslmanager (ED25519)';
const String _sha256Line = '256 SHA256:zzzz wslmanager (ED25519)';

CloudServer _running({String ip = '203.0.113.10', String name = 'deploy-1'}) =>
    CloudServer(
      id: '1',
      name: name,
      state: CloudServerState.running,
      provider: CloudProviderId.hetzner,
      ipv4: ip,
      labels: const {CloudServer.deployedInstanceLabel: 'Ubuntu'},
    );

void main() {
  late Directory tempDir;
  late Directory sshDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('cloud-deploy-test');
    sshDir = Directory('${tempDir.path}/ssh')..createSync(recursive: true);
    File('${sshDir.path}/id_ed25519.pub')
        .writeAsStringSync('ssh-ed25519 AAAAC3Nz key@host\n');
    SharedPreferences.setMockInitialValues({'DataPath': tempDir.path});
    prefs = await SharedPreferences.getInstance();
  });

  tearDown(() async {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  CloudDeployService service(
    FakeCloudShell shell,
    FakeCloudProvider provider, {
    FakeDeployBackend? backend,
  }) =>
      CloudDeployService(
        provider: provider,
        shell: shell,
        backend: backend ?? FakeDeployBackend(),
        sshDirectoryOverride: sshDir.path,
        pollInterval: Duration.zero,
        readyTimeout: const Duration(seconds: 5),
      );

  group('posix quoting', () {
    test('leaves shell-neutral tokens alone', () {
      expect(posixQuote('docker'), 'docker');
      expect(posixQuote('/root/Ubuntu-cloud.tar'), '/root/Ubuntu-cloud.tar');
      expect(posixQuote('root@203.0.113.10'), 'root@203.0.113.10');
    });

    test('quotes anything the remote shell would re-parse', () {
      // ssh joins its argv and the remote shell parses the result, so a space
      // or a metacharacter that arrives bare becomes a second argument — or a
      // second command.
      expect(posixQuote('two words'), "'two words'");
      expect(posixQuote(r'a;rm -rf /'), r"'a;rm -rf /'");
      expect(posixQuote(r'$(whoami)'), r"'$(whoami)'");
      expect(posixQuote("it's"), r"'it'\''s'");
    });

    test('builds a command line out of a whole argv', () {
      expect(posixCommandLine(['docker', 'run', '--name', 'a b']),
          "docker run --name 'a b'");
    });
  });

  test('cloud ssh accepts a new host key but not a changed one', () {
    final options = cloudSshOptions();
    // Without this the very first command against a server created seconds
    // ago fails: BatchMode turns the host-key prompt into a refusal.
    expect(options, contains('StrictHostKeyChecking=accept-new'));
    expect(options, contains('BatchMode=yes'));
    // And never the app's shared multiplexing socket: it has no %h in it, so
    // a master already open to the remote Windows host would swallow these
    // commands and run them on the wrong machine.
    expect(options.join(' '), isNot(contains('ControlPath')));
    expect(options.join(' '), isNot(contains('ControlMaster')));
  });

  test('deploys an instance end to end', () async {
    final shell = FakeCloudShell()
      ..responses['-E md5'] = _md5Line
      ..responses['-E sha256'] = _sha256Line;
    final provider = FakeCloudProvider()
      ..getServerAnswers.addAll([
        const CloudServer(
            id: '1',
            name: 'deploy-1',
            state: CloudServerState.initializing,
            provider: CloudProviderId.hetzner),
        _running(),
      ]);
    final backend = FakeDeployBackend();
    final stages = <DeployStage>[];

    final server = await service(shell, provider, backend: backend).deploy(
      instance: 'Ubuntu',
      serverName: 'deploy-1',
      serverType: 'cx22',
      image: 'ubuntu-24.04',
      location: 'nbg1',
      onProgress: (progress) => stages.add(progress.stage),
    );

    expect(server.address, '203.0.113.10');

    // Exported as a tarball, which is the only format `docker import` reads.
    expect(backend.exports.single[0], 'Ubuntu');
    expect(backend.exports.single[2], 'tar');

    // The create carries cloud-init and the label that makes the pull back
    // possible later.
    expect(provider.lastCreate['serverType'], 'cx22');
    expect(provider.lastCreate['userData'], contains('docker.io'));
    expect((provider.lastCreate['labels']! as Map)[
        CloudServer.deployedInstanceLabel], 'Ubuntu');

    expect(shell.sawCommand('test -f $cloudReadyMarker'), isTrue);
    final upload = shell.commandContaining('scp');
    expect(upload, contains('root@203.0.113.10:/root/Ubuntu-cloud.tar'));
    // The local side is a bare file name, never a full path: scp splits an
    // operand on its first colon, so `C:\\…\\Ubuntu-cloud.tar` reads as a
    // file on a host called `C` under any scp that does not special-case
    // Windows drive letters.
    expect(upload, contains(' Ubuntu-cloud.tar '));
    expect(upload, isNot(contains(tempDir.path)));
    expect(shell.sawCommand('docker import /root/Ubuntu-cloud.tar '
        'wslmanager/ubuntu'), isTrue);
    expect(shell.sawCommand('docker run --detach --name Ubuntu'), isTrue);
    expect(shell.sawCommand('sleep infinity'), isTrue);
    // The staged archive is removed on both ends.
    expect(shell.sawCommand('rm -f /root/Ubuntu-cloud.tar'), isTrue);
    expect(File('${tempDir.path}/tmp/Ubuntu-cloud.tar').existsSync(), isFalse);

    expect(stages.first, DeployStage.exporting);
    expect(stages.last, DeployStage.done);
    expect(stages, contains(DeployStage.waitingForDocker));
  });

  test('reuses an SSH key the provider already holds', () async {
    final shell = FakeCloudShell()
      ..responses['-E md5'] = _md5Line
      ..responses['-E sha256'] = _sha256Line;
    final provider = FakeCloudProvider(sshKeys: const [
      CloudSshKey(id: '42', name: 'other-machine', fingerprint: 'aa:bb:cc'),
    ])
      ..getServerAnswers.add(_running());

    await service(shell, provider).deploy(
      instance: 'Ubuntu',
      serverName: 'deploy-1',
      serverType: 'cx22',
      image: 'ubuntu-24.04',
      location: 'nbg1',
    );

    expect(provider.lastCreate['sshKeyIds'], ['42']);
    expect(provider.createdKeys, isEmpty);
  });

  test('uploads the key when the provider does not have it yet', () async {
    final shell = FakeCloudShell()
      ..responses['-E md5'] = _md5Line
      ..responses['-E sha256'] = _sha256Line;
    final provider = FakeCloudProvider(sshKeys: const [
      CloudSshKey(id: '42', name: 'someone-else', fingerprint: 'ff:ee:dd'),
    ])
      ..getServerAnswers.add(_running());

    await service(shell, provider).deploy(
      instance: 'Ubuntu',
      serverName: 'deploy-1',
      serverType: 'cx22',
      image: 'ubuntu-24.04',
      location: 'nbg1',
    );

    expect(provider.createdKeys, hasLength(1));
    expect(provider.lastCreate['sshKeyIds'], [provider.createdKeys.single.id]);
  });

  test('refuses to deploy without an SSH key, rather than creating a server '
      'nobody can reach', () async {
    // A provider that mails a root password instead is useless here: every
    // step after the create is an SSH command and password auth is off.
    final emptySsh = Directory('${tempDir.path}/no-keys')
      ..createSync(recursive: true);
    final shell = FakeCloudShell()..exitCodes['ssh-keygen'] = 1;
    final provider = FakeCloudProvider();

    await expectLater(
      CloudDeployService(
        provider: provider,
        shell: shell,
        backend: FakeDeployBackend(),
        sshDirectoryOverride: emptySsh.path,
        pollInterval: Duration.zero,
      ).deploy(
        instance: 'Ubuntu',
        serverName: 'deploy-1',
        serverType: 'cx22',
        image: 'ubuntu-24.04',
        location: 'nbg1',
      ),
      throwsA(isA<CloudException>()
          .having((e) => e.message, 'message', contains('SSH public key'))),
    );
    expect(provider.lastCreate, isEmpty);
  });

  test('keeps polling while the server is still initializing', () async {
    final shell = FakeCloudShell()
      ..responses['-E md5'] = _md5Line
      ..responses['-E sha256'] = _sha256Line;
    final provider = FakeCloudProvider()
      ..getServerAnswers.addAll([
        const CloudServer(
            id: '1',
            name: 'deploy-1',
            state: CloudServerState.initializing,
            provider: CloudProviderId.hetzner),
        const CloudServer(
            id: '1',
            name: 'deploy-1',
            state: CloudServerState.starting,
            provider: CloudProviderId.hetzner,
            ipv4: '203.0.113.10'),
        _running(),
      ]);

    await service(shell, provider).deploy(
      instance: 'Ubuntu',
      serverName: 'deploy-1',
      serverType: 'cx22',
      image: 'ubuntu-24.04',
      location: 'nbg1',
    );

    // An address alone is not enough — `starting` still has no sshd.
    expect(provider.getServerCalls, 3);
  });

  test('waits for cloud-init rather than racing the docker install', () async {
    final shell = FakeCloudShell()
      ..responses['-E md5'] = _md5Line
      ..responses['-E sha256'] = _sha256Line
      // The first two `test -f` calls fail, as they do while the server is
      // still installing Docker.
      ..failFirst['test -f $cloudReadyMarker'] = 2;
    final provider = FakeCloudProvider()..getServerAnswers.add(_running());

    await service(shell, provider).deploy(
      instance: 'Ubuntu',
      serverName: 'deploy-1',
      serverType: 'cx22',
      image: 'ubuntu-24.04',
      location: 'nbg1',
    );

    final probes = shell.commandLines
        .where((line) => line.contains('test -f $cloudReadyMarker'))
        .length;
    expect(probes, 3);
    // The import only runs after the marker appears.
    expect(shell.sawCommand('docker import'), isTrue);
  });

  test('a failing remote command surfaces the server\'s own stderr', () async {
    final shell = FakeCloudShell()
      ..responses['-E md5'] = _md5Line
      ..responses['-E sha256'] = _sha256Line
      ..exitCodes['docker import'] = 1
      ..errors['docker import'] = 'no space left on device';
    final provider = FakeCloudProvider()..getServerAnswers.add(_running());

    await expectLater(
      service(shell, provider).deploy(
        instance: 'Ubuntu',
        serverName: 'deploy-1',
        serverType: 'cx22',
        image: 'ubuntu-24.04',
        location: 'nbg1',
      ),
      throwsA(isA<CloudException>().having((e) => e.message, 'message',
          contains('no space left on device'))),
    );
    // The half-finished deploy still cleans up after itself locally.
    expect(File('${tempDir.path}/tmp/Ubuntu-cloud.tar').existsSync(), isFalse);
  });

  test('a backend that cannot export a rootfs never creates a server',
      () async {
    final shell = FakeCloudShell();
    final provider = FakeCloudProvider();
    final backend = FakeDeployBackend(rootfsExport: false);
    final deploy = service(shell, provider, backend: backend);

    expect(deploy.canDeploy, isFalse);
    await expectLater(
      deploy.deploy(
        instance: 'Ubuntu',
        serverName: 'deploy-1',
        serverType: 'cx22',
        image: 'ubuntu-24.04',
        location: 'nbg1',
      ),
      throwsA(isA<CloudException>()),
    );
    expect(provider.lastCreate, isEmpty);
    expect(backend.exports, isEmpty);
  });

  test('rejects a name that could arrive as another flag', () async {
    final deploy = service(FakeCloudShell(), FakeCloudProvider());

    await expectLater(
      deploy.deploy(
        instance: '--rm',
        serverName: 'deploy-1',
        serverType: 'cx22',
        image: 'ubuntu-24.04',
        location: 'nbg1',
      ),
      throwsA(isA<ArgumentError>()),
    );
    await expectLater(
      deploy.deploy(
        instance: 'Ubuntu',
        serverName: 'a name with spaces',
        serverType: 'cx22',
        image: 'ubuntu-24.04',
        location: 'nbg1',
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('pulls a deployed instance back under a new local name', () async {
    final shell = FakeCloudShell();
    final provider = FakeCloudProvider();
    final backend = FakeDeployBackend();
    final stages = <DeployStage>[];

    await service(shell, provider, backend: backend).pullBack(
      server: _running(),
      instance: 'Ubuntu',
      localName: 'Ubuntu-cloud',
      onProgress: (progress) => stages.add(progress.stage),
    );

    expect(
        shell.sawCommand(
            'docker export --output /root/Ubuntu-cloud-pull.tar Ubuntu'),
        isTrue);
    final download = shell.commandContaining('scp');
    expect(download, contains('root@203.0.113.10:/root/Ubuntu-cloud-pull.tar'));
    expect(download, isNot(contains(tempDir.path)));
    // Imported under the new name, never over the instance it came from.
    expect(backend.imports.single[0], 'Ubuntu-cloud');
    expect(stages, contains(DeployStage.downloading));
    expect(stages.last, DeployStage.done);
    // The server is left alone: pulling back is a copy, not a move.
    expect(provider.deleted, isEmpty);
    expect(provider.poweredOff, isEmpty);
  });

  test('refuses to pull from a server with no address', () async {
    await expectLater(
      service(FakeCloudShell(), FakeCloudProvider()).pullBack(
        server: const CloudServer(
            id: '1',
            name: 'deploy-1',
            state: CloudServerState.off,
            provider: CloudProviderId.hetzner),
        instance: 'Ubuntu',
        localName: 'Ubuntu-cloud',
      ),
      throwsA(isA<CloudException>()
          .having((e) => e.message, 'message', contains('no address'))),
    );
  });
}
