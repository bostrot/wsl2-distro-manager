import 'dart:io';
import 'package:dio/io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wsl2distromanager/api/docker_images.dart';
import 'package:wsl2distromanager/components/helpers.dart';

void main() {
  test('DockerImage configures proxy from prefs', () async {
    SharedPreferences.setMockInitialValues({'Proxy': 'http://127.0.0.1:8080'});
    await initPrefs();

    final dockerImage = DockerImage();
    final adapter = dockerImage.dio.httpClientAdapter;

    expect(adapter, isA<IOHttpClientAdapter>());
    final ioAdapter = adapter as IOHttpClientAdapter;
    
    expect(ioAdapter.createHttpClient, isNotNull);
    
    final client = ioAdapter.createHttpClient!();
    expect(client, isA<HttpClient>());
  });

  test('DockerImage does not configure proxy if pref is missing', () async {
    SharedPreferences.setMockInitialValues({});
    await initPrefs();

    final dockerImage = DockerImage();
    final adapter = dockerImage.dio.httpClientAdapter;

    expect(adapter, isA<IOHttpClientAdapter>());
    final ioAdapter = adapter as IOHttpClientAdapter;
    
    expect(ioAdapter.createHttpClient, isNull);
  });

  test('DockerImage configures registryUrl from prefs', () async {
    SharedPreferences.setMockInitialValues({'DockerRepoLink': 'https://mirror.gcr.io'});
    await initPrefs();

    final dockerImage = DockerImage();
    expect(dockerImage.registryUrl, equals('https://mirror.gcr.io'));
  });

  test('DockerImage uses default registryUrl if pref is missing', () async {
    SharedPreferences.setMockInitialValues({});
    await initPrefs();

    final dockerImage = DockerImage();
    expect(dockerImage.registryUrl, equals('https://registry-1.docker.io'));
  });
}
