import 'dart:io';

import 'package:dio/dio.dart';
import 'package:wsl2distromanager/api/cancellation.dart';
import 'package:wsl2distromanager/api/downloader.dart';
import 'package:wsl2distromanager/components/helpers.dart';

/// One downloadable installer in the macOS VM catalog.
///
/// The exact file name drifts with every point release, so an entry names a
/// mirror *directory* and a file pattern instead of a pinned URL — the same
/// trick [WSLApi.getDownloadable] uses to scrape a rootfs repo on Windows.
/// Resolution picks the highest version the listing offers.
class VmIsoCatalogEntry {
  final String name;
  final String indexUrl;
  final RegExp pattern;

  const VmIsoCatalogEntry({
    required this.name,
    required this.indexUrl,
    required this.pattern,
  });

  /// Stable slug the AI/MCP use to name an image, derived from [name]
  /// (e.g. "Alpine Linux (virt)" → "alpine-virt").
  String get id => name
      .toLowerCase()
      .replaceAll(RegExp(r'[()]'), '')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}

/// The curated arm64 installer ISOs the Create-VM page offers, and how they
/// are resolved, downloaded and cached.
class VmImageCatalog {
  VmImageCatalog({Dio? dio, ChunkedDownloaderFactory? downloaderFactory})
      : _dio = dio ?? Dio(),
        _downloaderFactory =
            downloaderFactory ?? defaultChunkedDownloaderFactory;

  final Dio _dio;
  final ChunkedDownloaderFactory _downloaderFactory;
  final Map<String, String> _resolved = {};

  /// Every mirror below is the distribution's own; all were live-verified
  /// 2026-09-01. `latest-stable`/`current` style paths keep an entry fresh
  /// across releases; Fedora pins a release directory because its layout has
  /// no such alias — the entry keeps working, it just stops being the newest
  /// when the next Fedora ships.
  static final List<VmIsoCatalogEntry> entries = [
    VmIsoCatalogEntry(
      name: 'Alpine Linux (virt)',
      indexUrl:
          'https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/aarch64/',
      pattern: RegExp(r'alpine-virt-[0-9.]+-aarch64\.iso'),
    ),
    VmIsoCatalogEntry(
      name: 'Alpine Linux (standard)',
      indexUrl:
          'https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/aarch64/',
      pattern: RegExp(r'alpine-standard-[0-9.]+-aarch64\.iso'),
    ),
    VmIsoCatalogEntry(
      name: 'Ubuntu Server 26.04 LTS',
      indexUrl: 'https://cdimage.ubuntu.com/releases/26.04/release/',
      pattern: RegExp(r'ubuntu-[0-9.]+-live-server-arm64\.iso'),
    ),
    VmIsoCatalogEntry(
      name: 'Debian (netinst)',
      indexUrl: 'https://cdimage.debian.org/debian-cd/current/arm64/iso-cd/',
      pattern: RegExp(r'debian-[0-9.]+-arm64-netinst\.iso'),
    ),
    VmIsoCatalogEntry(
      name: 'Fedora Server 44 (netinst)',
      indexUrl:
          'https://dl.fedoraproject.org/pub/fedora/linux/releases/44/Server/aarch64/iso/',
      pattern: RegExp(r'Fedora-Server-netinst-aarch64-[0-9.-]+\.iso'),
    ),
  ];

  static List<String> get names =>
      entries.map((entry) => entry.name).toList();

  /// The slug for [entry], for the MCP tools.
  static String idOf(VmIsoCatalogEntry entry) => entry.id;

  /// Look an entry up by its slug id.
  static VmIsoCatalogEntry? entryById(String id) {
    final needle = id.trim().toLowerCase();
    for (final entry in entries) {
      if (entry.id == needle) return entry;
    }
    return null;
  }

  static VmIsoCatalogEntry? entryFor(String name) {
    final trimmed = name.trim().toLowerCase();
    for (final entry in entries) {
      if (entry.name.toLowerCase() == trimmed) return entry;
    }
    return null;
  }

  /// Full URL of the newest ISO the entry's mirror listing offers.
  Future<String> resolveUrl(VmIsoCatalogEntry entry) async {
    final cached = _resolved[entry.name];
    if (cached != null) return cached;

    final response = await _dio.get<String>(entry.indexUrl,
        options: Options(responseType: ResponseType.plain));
    final matches = entry.pattern
        .allMatches(response.data ?? '')
        .map((match) => match.group(0)!)
        .toSet()
        .toList()
      ..sort(compareVersionish);
    if (matches.isEmpty) {
      throw Exception(
          'No installer matching ${entry.pattern.pattern} at ${entry.indexUrl}');
    }
    final url = entry.indexUrl + matches.last;
    _resolved[entry.name] = url;
    return url;
  }

  /// Orders file names so `3.10` beats `3.9`: digit runs compare as numbers,
  /// everything else as text.
  static int compareVersionish(String a, String b) {
    final digits = RegExp(r'\d+|\D+');
    final partsA = digits.allMatches(a).map((m) => m.group(0)!).toList();
    final partsB = digits.allMatches(b).map((m) => m.group(0)!).toList();
    for (var i = 0; i < partsA.length && i < partsB.length; i++) {
      final numA = int.tryParse(partsA[i]);
      final numB = int.tryParse(partsB[i]);
      final int result = (numA != null && numB != null)
          ? numA.compareTo(numB)
          : partsA[i].compareTo(partsB[i]);
      if (result != 0) return result;
    }
    return partsA.length.compareTo(partsB.length);
  }

  /// Where a resolved ISO lands on disk, keyed by its file name so a new
  /// point release downloads fresh while the old file still caches.
  static String cachePathFor(String url) {
    final fileName = url.split('/').last;
    return (getDataPath()..cd('isos')).file(fileName);
  }

  /// Downloads [entry]'s ISO into the cache (or reuses it) and returns the
  /// local path. Progress and cancellation mirror the WSL rootfs download:
  /// the finished file is checked against the announced size, and a partial
  /// file never stays behind to poison the cache.
  Future<String> download(
    VmIsoCatalogEntry entry, {
    void Function(int received, int total)? onProgress,
    CancelSignal? cancelSignal,
  }) async {
    final url = await resolveUrl(entry);
    final savePath = cachePathFor(url);
    final file = File(savePath);
    if (file.existsSync() && file.lengthSync() > 0) {
      return savePath;
    }

    final tmp = File('$savePath.tmp');
    if (tmp.existsSync()) tmp.deleteSync();

    var expectedBytes = -1;
    final downloader = _downloaderFactory(
      url: url,
      saveFilePath: savePath,
      onProgress: (count, total, speed) {
        expectedBytes = total;
        onProgress?.call(count, total);
      },
    );
    void stop() => downloader.stop();
    cancelSignal?.onCancel(stop);
    try {
      await downloader.start();
    } finally {
      if (cancelSignal != null) cancelSignal.removeListener(stop);
    }
    cancelSignal?.throwIfCancelled();

    final actualBytes = file.existsSync() ? file.lengthSync() : -1;
    if (actualBytes <= 0) {
      throw Exception('the server returned an empty file');
    }
    if (expectedBytes > 0 && actualBytes != expectedBytes) {
      file.deleteSync();
      throw Exception(
          'incomplete download, got $actualBytes of $expectedBytes bytes');
    }
    return savePath;
  }
}
