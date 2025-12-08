import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wsl2distromanager/api/docker_images.dart';
import 'package:wsl2distromanager/components/helpers.dart';

void main() {
  test('DockerImage configures mirror from prefs', () async {
    SharedPreferences.setMockInitialValues(
        {'DockerMirror': 'https://mirror.gcr.io'});
    await initPrefs();

    final dockerImage = DockerImage();
    expect(dockerImage.registryUrl, equals('https://mirror.gcr.io'));
  });

  test('DockerImage mirror overrides repo link', () async {
    SharedPreferences.setMockInitialValues({
      'DockerRepoLink': 'https://registry-1.docker.io',
      'DockerMirror': 'https://mirror.gcr.io'
    });
    await initPrefs();

    final dockerImage = DockerImage();
    expect(dockerImage.registryUrl, equals('https://mirror.gcr.io'));
  });

  test('DockerImage configures registryUrl from prefs', () async {
    SharedPreferences.setMockInitialValues(
        {'DockerRepoLink': 'https://mirror.gcr.io'});
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
