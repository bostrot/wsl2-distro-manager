import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wsl2distromanager/api/community_scripts.dart';
import 'package:wsl2distromanager/components/helpers.dart';

const String _info = 'name: redis\n'
    'description: Redis\n'
    'version: 1.0.0\n'
    'author: bostrot\n'
    'license: MIT\n'
    'git: https://github.com/bostrot/wsl-scripts\n'
    'distro:\n  - Debian\n  - Alpine\n';

const String _broken = 'this is not: valid: yaml: at all\n';

class _Adapter implements HttpClientAdapter {
  _Adapter({this.names = const ['redis'], this.brokenFor = const {}});
  final List<String> names;
  final Set<String> brokenFor;
  int commitCalls = 0;
  int listingCalls = 0;
  bool failCommits = false;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final path = options.uri.toString();
    if (path.contains('/commits')) {
      commitCalls++;
      if (failCommits) return ResponseBody.fromString('limited', 403);
      return ResponseBody.fromString(
          jsonEncode([
            {
              'commit': {
                'committer': {'date': '2026-08-20T08:00:00Z'}
              }
            }
          ]),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType]
          });
    }
    if (path.contains('api.github.com')) {
      listingCalls++;
      return ResponseBody.fromString(
          jsonEncode([for (final n in names) {'name': n}]), 200, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType]
      });
    }
    if (path.endsWith('info.yml')) {
      final name = names.firstWhere((n) => path.contains('/$n/'));
      return ResponseBody.fromString(
          brokenFor.contains(name) ? _broken : _info.replaceAll('redis', name),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.textPlainContentType]
          });
    }
    return ResponseBody.fromString('echo hi', 200);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    CommunityScripts.clearCache();
  });

  CommunityScripts build(_Adapter adapter) =>
      CommunityScripts(dio: Dio()..httpClientAdapter = adapter);

  test('a distro list in info.yml is exposed as a flat list', () async {
    final scripts = await build(_Adapter()).list();
    expect(scripts.single.distros, ['Debian', 'Alpine']);
  });

  test('the catalogue is cached until cleared or forced', () async {
    final adapter = _Adapter();
    final service = build(adapter);
    await service.list();
    await service.list();
    expect(adapter.listingCalls, 1);

    await service.list(force: true);
    expect(adapter.listingCalls, 2);
  });

  test('one malformed info.yml does not cost the whole catalogue', () async {
    final adapter =
        _Adapter(names: ['redis', 'broken', 'mysql'], brokenFor: {'broken'});
    final scripts = await build(adapter).list();
    expect(scripts.map((s) => s.name), ['redis', 'mysql']);
  });

  test('update dates are fetched once and then read from the cache',
      () async {
    final adapter = _Adapter();
    final service = build(adapter);
    final scripts = await service.list();

    await service.loadUpdatedDates(scripts);
    expect(scripts.single.updatedAt, DateTime.parse('2026-08-20T08:00:00Z'));
    expect(adapter.commitCalls, 1);

    // A fresh catalogue object with the same prefs must not re-request.
    CommunityScripts.clearCache();
    final again = await service.list(force: true);
    await service.loadUpdatedDates(again);
    expect(again.single.updatedAt, isNotNull);
    expect(adapter.commitCalls, 1, reason: 'the cached date should be reused');
  });

  test('a rate-limited commits API leaves dates null, not an exception',
      () async {
    final adapter = _Adapter()..failCommits = true;
    final service = build(adapter);
    final scripts = await service.list();

    await service.loadUpdatedDates(scripts);
    expect(scripts.single.updatedAt, isNull);
  });
}
