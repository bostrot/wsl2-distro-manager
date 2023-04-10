/// Tests for the wsl.dart file.
import 'package:flutter_test/flutter_test.dart';
import 'package:wsl2distromanager/api/wsl.dart';

void main() {
  test('Check update', () async {
    App app = App();
    var updateUrl = await app.checkUpdate('1.0.0');
    // Check if updateUrl contains https:// and .msix
    expect(updateUrl.contains('https://'), true);
    expect(updateUrl.contains('.msix'), true);
  });

  test('Version to double', () {
    App app = App();
    var version = app.versionToDouble('1.0.0');
    expect(version, 100.0);
  });

  test('Check motd', () async {
    App app = App();
    var motd = await app.checkMotd();
    expect(motd, isNotEmpty);
  });

  test('Get distro links', () async {
    App app = App();
    var links = await app.getDistroLinks();
    expect(links, isNotEmpty);
  });

  test('UTF16 to UTF8', () {
    WSLApi app = WSLApi();
    // Create a UTF16 string
    var utf16 = 'Hello World';
    // To bytes
    var bytes = utf16.codeUnits;
    // Add 0 between each byte
    var bytes2 = bytes.expand((e) => [e, 0]).toList();

    // Convert to UTF8
    var utf8 = app.utf8Convert(bytes2);
    expect(utf8, utf16);
  });
}
