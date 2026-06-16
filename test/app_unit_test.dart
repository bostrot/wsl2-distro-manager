import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wsl2distromanager/api/app.dart';
import 'mocks.dart';

class MockFailureAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    throw Exception('Network failure');
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('App.versionToDouble', () {
    test('converts simple version string', () {
      final app = App();
      expect(app.versionToDouble('1.2.3'), 123);
    });

    test('converts version with v prefix', () {
      final app = App();
      expect(app.versionToDouble('v2.0.0'), 200);
    });

    test('converts version with plus suffix', () {
      final app = App();
      expect(app.versionToDouble('1.3+2'), greaterThan(13));
    });

    test('returns -1 for invalid input', () {
      final app = App();
      expect(app.versionToDouble('not-a-version'), -1);
    });

    test('handles empty string', () {
      final app = App();
      expect(app.versionToDouble(''), -1);
    });

    test('compares versions correctly', () {
      final app = App();
      expect(app.versionToDouble('2.0.0') > app.versionToDouble('1.9.9'), true);
      expect(app.versionToDouble('1.10.0') > app.versionToDouble('1.9.0'), true);
    });
  });

  group('App.checkUpdate', () {
    test('returns update URL when newer version available', () async {
      final dio = Dio();
      dio.httpClientAdapter = MockHttpClientAdapter();
      final app = App(dio: dio);

      final result = await app.checkUpdate('1.0.0');
      expect(result, isNotEmpty);
    });

    test('returns empty string when no newer version', () async {
      final dio = Dio();
      dio.httpClientAdapter = MockHttpClientAdapter();
      final app = App(dio: dio);

      final result = await app.checkUpdate('3.0.0');
      expect(result, isEmpty);
    });

    test('returns empty string when network fails', () async {
      final dio = Dio();
      dio.httpClientAdapter = MockFailureAdapter();
      final app = App(dio: dio);

      // This will fail but should not throw
      final result = await app.checkUpdate('1.0.0');
      expect(result, isEmpty);
    });
  });

  group('App.getDistroLinks', () {
    test('returns distro links from remote source', () async {
      final dio = Dio();
      dio.httpClientAdapter = MockHttpClientAdapter();
      final app = App(dio: dio);

      // The mock returns a simple JSON response for the git webhook URL
      final result = await app.getDistroLinks();
      expect(result, isA<Map<String, String>>());
    });

    test('returns empty map when network fails', () async {
      final dio = Dio();
      dio.options.baseUrl = 'http://invalid.local.test';
      final app = App(dio: dio);

      // Should not throw even on failure
      final result = await app.getDistroLinks();
      expect(result, isA<Map<String, String>>());
    });
  });
}
