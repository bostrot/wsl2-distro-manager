import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:chunked_downloader/chunked_downloader.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wsl2distromanager/api/apple/vm_image_catalog.dart';
import 'package:wsl2distromanager/api/cancellation.dart';
import 'package:wsl2distromanager/components/helpers.dart';

/// Serves canned directory listings for the catalog's mirror indexes.
class _FakeListingAdapter implements HttpClientAdapter {
  final Map<String, String> pages;
  final List<String> requested = [];
  _FakeListingAdapter(this.pages);

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requested.add(options.uri.toString());
    for (final entry in pages.entries) {
      if (options.uri.toString().startsWith(entry.key)) {
        return ResponseBody.fromString(entry.value, 200);
      }
    }
    return ResponseBody.fromString('not found', 404);
  }

  @override
  void close({bool force = false}) {}
}

/// A downloader whose "network" is a byte payload handed in by the test.
class _FakeDownloader implements ChunkedDownloader {
  _FakeDownloader({
    required this.url,
    required this.saveFilePath,
    this.onProgress,
    this.payload = const [1, 2, 3],
    this.announceTotal,
    this.failWith,
  });

  @override
  final String url;
  @override
  final String saveFilePath;
  @override
  final Function(int, int, double)? onProgress;
  final List<int> payload;
  final int? announceTotal;
  final Object? failWith;
  bool stopped = false;

  @override
  Future<ChunkedDownloader> start() async {
    if (failWith != null) throw failWith!;
    onProgress?.call(
        payload.length, announceTotal ?? payload.length, 1000);
    if (!stopped) {
      final file = File(saveFilePath);
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(payload);
    }
    return this;
  }

  @override
  void stop() {
    stopped = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dataDir;

  setUp(() async {
    dataDir = Directory.systemTemp.createTempSync('iso-catalog-test');
    SharedPreferences.setMockInitialValues({'DataPath': dataDir.path});
    prefs = await SharedPreferences.getInstance();
  });

  tearDown(() {
    if (dataDir.existsSync()) dataDir.deleteSync(recursive: true);
  });

  VmIsoCatalogEntry alpine() => VmImageCatalog.entryFor('Alpine Linux (virt)')!;

  Dio fakeDio(Map<String, String> pages) =>
      Dio()..httpClientAdapter = _FakeListingAdapter(pages);

  group('catalog shape', () {
    test('the ready-to-use cloud image is curated and marked as such', () {
      final entry = VmImageCatalog.entryById('debian-13-cloud');
      expect(entry, isNotNull);
      expect(entry!.isCloudImage, isTrue);
      expect(entry.pattern.pattern, contains('genericcloud-arm64'));
      expect(entry.pattern.pattern, contains('raw'),
          reason: 'only raw images boot without a conversion tool');
      // Alpine's cloud image rides the same path (qcow2, converted by
      // vmctl); everything else stays an installer.
      expect(
          VmImageCatalog.entries
              .where((e) => e.isCloudImage)
              .map((e) => e.id),
          ['debian-13-cloud', 'alpine-cloud']);
      final alpine = VmImageCatalog.entryById('alpine-cloud')!;
      expect(alpine.pattern.pattern, isNot(contains('metal')));
      expect('generic_alpine-3.24.1-aarch64-uefi-cloudinit-metal-r0.qcow2',
          isNot(matches(alpine.pattern)));
      expect('generic_alpine-3.24.1-aarch64-uefi-cloudinit-r0.qcow2',
          matches(alpine.pattern));
    });

    test('names cover the curated distros and resolve back to entries', () {
      expect(VmImageCatalog.names.length, greaterThanOrEqualTo(4));
      for (final name in VmImageCatalog.names) {
        expect(VmImageCatalog.entryFor(name), isNotNull);
      }
      // Lookup is case-insensitive — the box's text is user-typed.
      expect(VmImageCatalog.entryFor('alpine linux (VIRT)'), isNotNull);
      expect(VmImageCatalog.entryFor('/tmp/some/local.iso'), isNull);
      expect(VmImageCatalog.entryFor(''), isNull);
    });
  });

  group('version-aware ordering', () {
    test('numeric runs compare as numbers, not text', () {
      final names = [
        'alpine-virt-3.9.2-aarch64.iso',
        'alpine-virt-3.24.1-aarch64.iso',
        'alpine-virt-3.24.0-aarch64.iso',
      ]..sort(VmImageCatalog.compareVersionish);
      expect(names.last, 'alpine-virt-3.24.1-aarch64.iso');
      expect(names.first, 'alpine-virt-3.9.2-aarch64.iso');
    });
  });

  group('resolveUrl', () {
    test('scrapes the listing and picks the newest match', () async {
      final entry = alpine();
      final catalog = VmImageCatalog(dio: fakeDio({
        entry.indexUrl: '<a href="alpine-virt-3.24.0-aarch64.iso">x</a>'
            '<a href="alpine-virt-3.24.1-aarch64.iso">y</a>'
            '<a href="alpine-standard-3.24.1-aarch64.iso">z</a>',
      }));
      expect(await catalog.resolveUrl(entry),
          '${entry.indexUrl}alpine-virt-3.24.1-aarch64.iso');
    });

    test('a listing with no match is an error, not a null download', () {
      final entry = alpine();
      final catalog =
          VmImageCatalog(dio: fakeDio({entry.indexUrl: '<html>empty</html>'}));
      expect(() => catalog.resolveUrl(entry), throwsException);
    });

    test('resolution is cached per catalog instance', () async {
      final entry = alpine();
      final adapter = _FakeListingAdapter({
        entry.indexUrl: '<a href="alpine-virt-3.24.1-aarch64.iso">y</a>',
      });
      final catalog = VmImageCatalog(dio: Dio()..httpClientAdapter = adapter);
      await catalog.resolveUrl(entry);
      await catalog.resolveUrl(entry);
      expect(adapter.requested, hasLength(1));
    });
  });

  group('download', () {
    VmImageCatalog catalogWith(_FakeDownloader Function(
            {required String url,
            required String saveFilePath,
            Function(int, int, double)? onProgress})
        make) {
      final entry = alpine();
      return VmImageCatalog(
        dio: fakeDio({
          entry.indexUrl: '<a href="alpine-virt-3.24.1-aarch64.iso">y</a>',
        }),
        downloaderFactory: ({
          required url,
          required saveFilePath,
          headers,
          chunkSize,
          onProgress,
          onDone,
          onError,
        }) =>
            make(url: url, saveFilePath: saveFilePath, onProgress: onProgress),
      );
    }

    test('fetches into the iso cache and reports progress', () async {
      final progress = <List<int>>[];
      final catalog = catalogWith(
          ({required url, required saveFilePath, onProgress}) =>
              _FakeDownloader(
                  url: url,
                  saveFilePath: saveFilePath,
                  onProgress: onProgress,
                  payload: List.filled(64, 7)));
      final path = await catalog.download(alpine(),
          onProgress: (received, total) => progress.add([received, total]));
      expect(path, contains('isos'));
      expect(path, endsWith('alpine-virt-3.24.1-aarch64.iso'));
      expect(File(path).lengthSync(), 64);
      expect(progress, isNotEmpty);
    });

    test('a cached file is reused without a new download', () async {
      var downloads = 0;
      final catalog = catalogWith(
          ({required url, required saveFilePath, onProgress}) {
        downloads++;
        return _FakeDownloader(
            url: url, saveFilePath: saveFilePath, onProgress: onProgress);
      });
      await catalog.download(alpine());
      await catalog.download(alpine());
      expect(downloads, 1);
    });

    test('a short download is deleted and reported, not cached', () async {
      final catalog = catalogWith(
          ({required url, required saveFilePath, onProgress}) =>
              _FakeDownloader(
                  url: url,
                  saveFilePath: saveFilePath,
                  onProgress: onProgress,
                  payload: List.filled(10, 1),
                  // The server announced more than arrived.
                  announceTotal: 999));
      await expectLater(
          catalog.download(alpine()),
          throwsA(predicate(
              (e) => e.toString().contains('incomplete download'))));
      final cache = Directory('${dataDir.path}/isos');
      expect(
          cache.existsSync() &&
              cache.listSync().any((f) => f.path.endsWith('.iso')),
          isFalse,
          reason: 'a partial file must not poison the cache');
    });

    test('a downloader error propagates and leaves nothing cached', () async {
      final catalog = catalogWith(
          ({required url, required saveFilePath, onProgress}) =>
              _FakeDownloader(
                  url: url,
                  saveFilePath: saveFilePath,
                  onProgress: onProgress,
                  failWith: const SocketException('connection reset')));
      await expectLater(
          catalog.download(alpine()), throwsA(isA<SocketException>()));
      final cache = Directory('${dataDir.path}/isos');
      expect(
          cache.existsSync() &&
              cache.listSync().any((f) => f.path.endsWith('.iso')),
          isFalse,
          reason: 'a failed download must not leave a file behind');
    });

    test('cancel stops the downloader and surfaces as CancelledException',
        () async {
      _FakeDownloader? made;
      final signal = CancelSignal();
      final catalog = catalogWith(
          ({required url, required saveFilePath, onProgress}) {
        made = _FakeDownloader(
            url: url,
            saveFilePath: saveFilePath,
            onProgress: (c, t, s) {
              signal.cancel();
              onProgress?.call(c, t, s);
            });
        return made!;
      });
      await expectLater(catalog.download(alpine(), cancelSignal: signal),
          throwsA(isA<CancelledException>()));
      expect(made!.stopped, isTrue);
    });
  });
}
