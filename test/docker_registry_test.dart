import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wsl2distromanager/api/docker_images.dart';
import 'package:wsl2distromanager/components/helpers.dart';

class MockRegistryHttpClientAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final uri = options.uri;

    // 1. Quay.io /v2/ check
    if (uri.toString() == 'https://quay.io/v2/') {
      return ResponseBody.fromString(
        '',
        401,
        headers: {
          Headers.wwwAuthenticateHeader: [
            'Bearer realm="https://quay.io/v2/auth",service="quay.io"'
          ],
        },
      );
    }

    // 2. Quay.io Auth
    if (uri.toString().startsWith('https://quay.io/v2/auth')) {
      if (uri.queryParameters['service'] == 'quay.io' &&
          uri.queryParameters['scope'] == 'repository:centos/centos:pull') {
        return ResponseBody.fromString(
          jsonEncode({'token': 'quay_fake_token'}),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType]
          },
        );
      }
    }

    // 3. Quay.io Manifest
    if (uri.toString() ==
        'https://quay.io/v2/centos/centos/manifests/stream10') {
      if (options.headers['Authorization'] == 'Bearer quay_fake_token') {
        return ResponseBody.fromString(
          jsonEncode({
            'schemaVersion': 2,
            'mediaType': 'application/vnd.docker.distribution.manifest.v2+json',
            'config': {
              'mediaType': 'application/vnd.docker.container.image.v1+json',
              'size': 123,
              'digest': 'sha256:fakeconfigdigest'
            },
            'layers': []
          }),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType]
          },
        );
      } else {
        return ResponseBody.fromString('Unauthorized', 401);
      }
    }

    // 4. Docker Hub /v2/ check (default behavior)
    if (uri.toString() == 'https://registry-1.docker.io/v2/') {
      return ResponseBody.fromString(
        '',
        401,
        headers: {
          Headers.wwwAuthenticateHeader: [
            'Bearer realm="https://auth.docker.io/token",service="registry.docker.io"'
          ],
        },
      );
    }

    // 5. Docker Hub Auth
    if (uri.toString().startsWith('https://auth.docker.io/token')) {
      if (uri.queryParameters['service'] == 'registry.docker.io' &&
          (uri.queryParameters['scope'] == 'repository:library/alpine:pull' ||
              uri.queryParameters['scope'] == 'repository:alpine:pull')) {
        return ResponseBody.fromString(
          jsonEncode({'token': 'docker_fake_token'}),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType]
          },
        );
      }
    }

    // 6. Docker Hub Manifest
    if (uri.toString() ==
        'https://registry-1.docker.io/v2/library/alpine/manifests/latest') {
      if (options.headers['Authorization'] == 'Bearer docker_fake_token') {
        return ResponseBody.fromString(
          jsonEncode({
            'schemaVersion': 2,
            'mediaType': 'application/vnd.docker.distribution.manifest.v2+json',
            'config': {
              'mediaType': 'application/vnd.docker.container.image.v1+json',
              'size': 123,
              'digest': 'sha256:fakeconfigdigest'
            },
            'layers': []
          }),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType]
          },
        );
      }
    }

    return ResponseBody.fromString('Not Found: ${uri.toString()}', 404);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await initPrefs();
  });

  test('DockerImage: Custom Registry (quay.io)', () async {
    final dio = Dio();
    dio.httpClientAdapter = MockRegistryHttpClientAdapter();

    final dockerImage = DockerImage(dio: dio);

    // Test hasImage with a custom registry image
    final result =
        await dockerImage.hasImage('quay.io/centos/centos', tag: 'stream10');

    expect(result, true);
    expect(dockerImage.registryUrl, 'https://quay.io');
    expect(dockerImage.authUrl, 'https://quay.io/v2/auth');
    expect(dockerImage.svcUrl, 'quay.io');
  });

  test('DockerImage: Default Registry (Docker Hub)', () async {
    final dio = Dio();
    dio.httpClientAdapter = MockRegistryHttpClientAdapter();

    final dockerImage = DockerImage(dio: dio);

    // Test hasImage with a default image
    final result = await dockerImage.hasImage('alpine', tag: 'latest');

    expect(result, true);
    // Should remain default or be updated to what _setupRegistry finds (which is the same)
    expect(dockerImage.registryUrl, 'https://registry-1.docker.io');
    // Note: _setupRegistry might update authUrl based on the 401 response from registry-1.docker.io
    // which returns realm="https://auth.docker.io/token"
    expect(dockerImage.authUrl, 'https://auth.docker.io/token');
    expect(dockerImage.svcUrl, 'registry.docker.io');
  });
}
