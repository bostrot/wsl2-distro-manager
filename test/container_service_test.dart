import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wsl2distromanager/api/containers/container_models.dart';
import 'package:wsl2distromanager/api/containers/container_service.dart';
import 'package:wsl2distromanager/components/helpers.dart';

import 'fake_container_shell.dart';

/// `ps --format` output: the tab-separated template the service asks for.
String psLine(String id, String name, String image, String state,
        [String status = '', String ports = '']) =>
    [id, name, image, state, status, ports].join('\t');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeContainerShell shell;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    shell = FakeContainerShell();
  });

  ContainerService service({Duration? timeout}) => ContainerService(
      shell: shell, timeout: timeout ?? const Duration(seconds: 30));

  group('parsePsOutput', () {
    test('reads every field of a row', () {
      final containers = ContainerService.parsePsOutput(
        psLine('abc123', 'web', 'nginx:latest', 'running', 'Up 2 hours',
            '0.0.0.0:8080->80/tcp'),
        ContainerEngine.docker,
      );

      expect(containers, hasLength(1));
      final container = containers.single;
      expect(container.id, 'abc123');
      expect(container.name, 'web');
      expect(container.image, 'nginx:latest');
      expect(container.state, ContainerState.running);
      expect(container.status, 'Up 2 hours');
      expect(container.ports, '0.0.0.0:8080->80/tcp');
      expect(container.engine, ContainerEngine.docker);
      expect(container.ref, 'web');
    });

    test('falls back to the status word when .State comes back empty', () {
      // Engines older than the `.State` field leave that column blank; the
      // first word of `.Status` is the same information.
      final containers = ContainerService.parsePsOutput(
        psLine('abc123', 'web', 'nginx', '', 'Exited (0) 3 minutes ago'),
        ContainerEngine.podman,
      );
      expect(containers.single.state, ContainerState.exited);
    });

    test('keeps an unknown state instead of dropping the row', () {
      final containers = ContainerService.parsePsOutput(
        psLine('abc123', 'web', 'nginx', 'wedged'),
        ContainerEngine.docker,
      );
      expect(containers.single.state, ContainerState.unknown);
      expect(containers.single.name, 'web');
    });

    test('skips banner lines that are not containers', () {
      // podman-docker prints this on stdout before the table.
      final output = [
        'Emulate Docker CLI using podman. Create /etc/containers/nodocker',
        '',
        psLine('abc123', 'web', 'nginx', 'running'),
      ].join('\n');

      final containers =
          ContainerService.parsePsOutput(output, ContainerEngine.podman);
      expect(containers, hasLength(1));
      expect(containers.single.name, 'web');
    });

    test('falls back to the id when a container has no name', () {
      final containers = ContainerService.parsePsOutput(
        psLine('abc123', '', 'nginx', 'running'),
        ContainerEngine.docker,
      );
      expect(containers.single.ref, 'abc123');
    });
  });

  group('engine detection', () {
    test('finds only the engines that answer --version', () async {
      shell.missing.add('podman');
      final engines = await service().availableEngines();
      expect(engines, [ContainerEngine.docker]);
    });

    test('reports none when neither engine is installed', () async {
      shell.missing.addAll(['docker', 'podman']);
      expect(await service().availableEngines(), isEmpty);
      expect(await service().activeEngine(), isNull);
    });

    test('the pinned engine wins over probe order', () async {
      final api = service();
      await api.setPreferredEngine(ContainerEngine.podman);
      expect(await api.activeEngine(), ContainerEngine.podman);
    });

    test('a pinned engine that is not installed falls back', () async {
      shell.missing.add('podman');
      final api = service();
      await api.setPreferredEngine(ContainerEngine.podman);
      expect(await api.activeEngine(), ContainerEngine.docker);
    });

    test('the probe is cached until it is invalidated', () async {
      final api = service();
      await api.availableEngines();
      final probes = shell.calls.length;
      await api.availableEngines();
      expect(shell.calls.length, probes);

      api.invalidateEngineCache();
      await api.availableEngines();
      expect(shell.calls.length, greaterThan(probes));
    });
  });

  group('list', () {
    test('asks the engine for stopped containers too', () async {
      shell.responses['docker ps'] = psLine('a1', 'web', 'nginx', 'running');
      await service().list(engine: ContainerEngine.docker);

      final call = shell.calls.last;
      expect(call.first, 'docker');
      expect(call, contains('--all'));
      expect(call, contains('--format'));
    });

    test('running-only drops the --all flag', () async {
      shell.responses['docker ps'] = '';
      await service()
          .list(engine: ContainerEngine.docker, runningOnly: true);
      expect(shell.calls.last, isNot(contains('--all')));
    });

    test("surfaces the engine's own error when the daemon is down", () async {
      shell.exitCodes['docker ps'] = 1;
      shell.errors['docker ps'] =
          'Cannot connect to the Docker daemon at unix:///var/run/docker.sock';

      expect(
        () => service().list(engine: ContainerEngine.docker),
        throwsA(isA<ContainerException>().having((e) => e.message, 'message',
            contains('Cannot connect to the Docker daemon'))),
      );
    });

    test('without any engine it says so instead of failing obscurely',
        () async {
      shell.missing.addAll(['docker', 'podman']);
      expect(
        () => service().list(),
        throwsA(isA<ContainerException>().having((e) => e.message, 'message',
            contains('No container engine found'))),
      );
    });
  });

  group('listAll', () {
    test('merges both engines and tags each row with its origin', () async {
      shell.responses['docker ps'] = psLine('a1', 'web', 'nginx', 'running');
      shell.responses['podman ps'] = psLine('b2', 'db', 'postgres', 'exited');

      final containers = await service().listAll();
      expect(containers.map((c) => c.name), ['web', 'db']);
      expect(containers.map((c) => c.engine),
          [ContainerEngine.docker, ContainerEngine.podman]);
    });

    test('one broken engine does not hide the other', () async {
      shell.responses['docker ps'] = psLine('a1', 'web', 'nginx', 'running');
      shell.exitCodes['podman ps'] = 125;
      shell.errors['podman ps'] = 'podman machine is not running';

      final containers = await service().listAll();
      expect(containers.map((c) => c.name), ['web']);
    });

    test('when every engine fails both messages are reported', () async {
      shell.exitCodes['docker ps'] = 1;
      shell.errors['docker ps'] = 'Cannot connect to the Docker daemon';
      shell.exitCodes['podman ps'] = 125;
      shell.errors['podman ps'] = 'podman machine is not running';

      expect(
        service().listAll(),
        throwsA(isA<ContainerException>().having(
            (e) => e.message,
            'message',
            allOf(contains('Cannot connect to the Docker daemon'),
                contains('podman machine is not running')))),
      );
    });
  });

  group('lifecycle', () {
    test('start, stop and restart pass the container through', () async {
      final api = service();
      await api.start(ContainerEngine.docker, 'web');
      expect(shell.calls.last, ['docker', 'start', 'web']);

      await api.stop(ContainerEngine.docker, 'web');
      expect(shell.calls.last, ['docker', 'stop', 'web']);

      await api.restart(ContainerEngine.podman, 'web');
      expect(shell.calls.last, ['podman', 'restart', 'web']);
    });

    test('remove only forces when asked', () async {
      final api = service();
      await api.remove(ContainerEngine.docker, 'web');
      expect(shell.calls.last, ['docker', 'rm', 'web']);

      await api.remove(ContainerEngine.docker, 'web', force: true);
      expect(shell.calls.last, ['docker', 'rm', '--force', 'web']);
    });

    test('a failing verb reports the exit code and the engine text', () async {
      shell.exitCodes['docker stop'] = 1;
      shell.errors['docker stop'] = 'No such container: web';

      expect(
        () => service().stop(ContainerEngine.docker, 'web'),
        throwsA(isA<ContainerException>().having((e) => e.message, 'message',
            allOf(contains('exit 1'), contains('No such container')))),
      );
    });

    test('a name that could pass for a flag is refused', () async {
      final api = service();
      for (final bad in ['--rm', '-f', 'web;rm -rf /', '', 'a b']) {
        expect(() => api.stop(ContainerEngine.docker, bad),
            throwsA(isA<ArgumentError>()),
            reason: '"$bad" must not reach the command line');
      }
      expect(shell.calls, isEmpty);
    });
  });

  group('logs and exec', () {
    test('logs bound the output and merge both streams', () async {
      shell.responses['docker logs'] = 'listening on :80';
      shell.errors['docker logs'] = 'warning: no config file';

      final output =
          await service().logs(ContainerEngine.docker, 'web', lines: 50);
      expect(shell.calls.last, ['docker', 'logs', '--tail', '50', 'web']);
      expect(output, contains('listening on :80'));
      expect(output, contains('warning: no config file'));
    });

    test('a non-positive line count is refused', () async {
      expect(() => service().logs(ContainerEngine.docker, 'web', lines: 0),
          throwsA(isA<ArgumentError>()));
    });

    test('exec runs the command through the container shell', () async {
      shell.responses['docker exec'] = 'root';
      final output =
          await service().exec(ContainerEngine.docker, 'web', 'whoami');
      expect(shell.calls.last, ['docker', 'exec', 'web', 'sh', '-c', 'whoami']);
      expect(output, 'root');
    });

    test('a failing exec carries the command output, not just a code',
        () async {
      shell.exitCodes['docker exec'] = 127;
      shell.errors['docker exec'] = 'sh: nope: not found';

      expect(
        () => service().exec(ContainerEngine.docker, 'web', 'nope'),
        throwsA(isA<ContainerException>().having((e) => e.message, 'message',
            allOf(contains('127'), contains('not found')))),
      );
    });

    test('an empty command never reaches the engine', () async {
      expect(() => service().exec(ContainerEngine.docker, 'web', '   '),
          throwsA(isA<ArgumentError>()));
      expect(shell.calls, isEmpty);
    });
  });

  test('a hung engine is killed, not just stopped being awaited', () async {
    shell.hangs.add('docker ps');
    final api = service(timeout: const Duration(milliseconds: 50));

    await expectLater(
      api.list(engine: ContainerEngine.docker),
      throwsA(isA<ContainerException>()
          .having((e) => e.message, 'message', contains('did not answer'))),
    );
    // Abandoning the future would leave the child running; the point of
    // going through ExecutionBroker is that it reaps it.
    expect(shell.started.single.killCount, greaterThan(0));
  });

  test('with a remote WSL target the command runs over ssh', () async {
    SharedPreferences.setMockInitialValues({
      'UseRemoteWSL': true,
      'RemoteWSLTarget': 'user@host',
    });
    prefs = await SharedPreferences.getInstance();

    await service().start(ContainerEngine.docker, 'web');

    final call = shell.calls.last;
    expect(call.first, 'ssh');
    expect(call, contains('user@host'));
    expect(call.join(' '), contains('docker'));
    expect(call.join(' '), contains('start'));
  });

  // Read-only host inspection (bostrot/ai-tasks#67).
  group('read-only inspection', () {
    test('stats never streams', () async {
      // Without --no-stream `docker stats` never exits, so this would hit the
      // broker's timeout on every call instead of answering.
      shell.responses['docker stats'] = 'web\t2.5%';
      await service().stats(ContainerEngine.docker);
      expect(shell.calls.single, contains('--no-stream'));
    });

    test('stats for one container puts the ref after the flags', () async {
      shell.responses['docker stats'] = 'web\t2.5%';
      await service().stats(ContainerEngine.docker, ref: 'web');
      expect(shell.calls.single.last, 'web');
    });

    test('a ref that could pass for a flag is refused', () async {
      await expectLater(
          service().stats(ContainerEngine.docker, ref: '--format={{.X}}'),
          throwsArgumentError);
      await expectLater(
          service().processes(ContainerEngine.docker, '-a'),
          throwsArgumentError);
      expect(shell.calls, isEmpty);
    });

    test('images, volumes, networks and disk usage each run their own read',
        () async {
      final api = service();
      shell.responses['docker images'] = 'nginx:latest\ta1';
      shell.responses['docker volume'] = 'pgdata\tlocal';
      shell.responses['docker network'] = 'bridge\tbridge\tlocal';
      shell.responses['docker system'] = 'TYPE';
      expect(await api.images(ContainerEngine.docker), contains('nginx'));
      expect(await api.volumes(ContainerEngine.docker), contains('pgdata'));
      expect(await api.networks(ContainerEngine.docker), contains('bridge'));
      expect(await api.diskUsage(ContainerEngine.docker), contains('TYPE'));
      // Nothing in the family can prune, remove or build.
      expect(
          shell.calls.map((c) => c.join(' ')),
          everyElement(allOf(isNot(contains('prune')), isNot(contains(' rm ')),
              isNot(contains('build')))));
    });

    test("a refusing daemon surfaces the engine's own words", () async {
      shell.exitCodes['docker images'] = 1;
      shell.errors['docker images'] = 'Cannot connect to the Docker daemon';
      await expectLater(
          service().images(ContainerEngine.docker),
          throwsA(isA<ContainerException>().having((e) => e.message, 'message',
              contains('Cannot connect to the Docker daemon'))));
    });
  });

  group('logs options', () {
    test('since and timestamps are engine flags, and the ref stays last',
        () async {
      shell.responses['docker logs'] = 'line';
      await service().logs(ContainerEngine.docker, 'web',
          since: '15m', timestamps: true);
      final call = shell.calls.single;
      expect(call, contains('--since=15m'));
      expect(call, contains('--timestamps'));
      expect(call.last, 'web');
    });

    test('a since that is not a duration never reaches the engine', () async {
      await expectLater(
          service().logs(ContainerEngine.docker, 'web', since: '2026-09-01'),
          throwsArgumentError);
      expect(shell.calls, isEmpty);
    });
  });
}
