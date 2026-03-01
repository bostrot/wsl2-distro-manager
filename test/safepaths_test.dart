/// Tests for the safe_paths class.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wsl2distromanager/api/safe_paths.dart';

void main() {
  test('SafePath init', () async {
    SafePath safePath = SafePath('C:\\test');
    expect(safePath.path, 'C:\\test');
    // Delete if empty
    if (await Directory(safePath.path).list().isEmpty) {
      Directory(safePath.path).deleteSync();
    }
  });

  test('SafePath dir up', () async {
    SafePath safePath = SafePath('C:\\test\\test2');
    safePath.cdUp();
    expect(safePath.path, 'C:\\test');
    // Delete if empty
    if (await Directory('C:\\test\\test2').list().isEmpty) {
      Directory('C:\\test\\test2').deleteSync();
    }
    if (await Directory(safePath.path).list().isEmpty) {
      Directory(safePath.path).deleteSync();
    }
  });

  test('SafePath cd', () async {
    SafePath safePath = SafePath('C:\\test');
    safePath.cd('test2');
    expect(safePath.path, 'C:\\test\\test2');
    // Delete if empty
    if (await Directory(safePath.path).list().isEmpty) {
      Directory(safePath.path).deleteSync();
    }
    if (await Directory('C:\\test').list().isEmpty) {
      Directory('C:\\test').deleteSync();
    }
  });

  test('SafePath file', () async {
    SafePath safePath = SafePath('C:\\test');
    // Create file test2 in test
    File file = File('C:\\test\\test2');
    file.createSync();
    expect(safePath.file('test2'), 'C:\\test\\test2');
    // Delete file
    file.deleteSync();
    // Delete if empty
    if (await Directory(safePath.path).list().isEmpty) {
      Directory(safePath.path).deleteSync();
    }
  });

  test('SafePath parent', () async {
    SafePath safePath = SafePath('C:\\test\\test2');
    expect(safePath.parent, 'C:\\test');
    // Delete if empty
    if (await Directory(safePath.path).list().isEmpty) {
      Directory(safePath.path).deleteSync();
    }
    if (await Directory('C:\\test').list().isEmpty) {
      Directory('C:\\test').deleteSync();
    }
  });

  test('SafePath creation and normalization', () async {
    String path = 'C:/test_safepath_creation';
    // Ensure clean state
    if (Directory(path).existsSync()) {
      Directory(path).deleteSync(recursive: true);
    }

    SafePath safePath = SafePath(path);
    expect(Directory(path).existsSync(), true);
    // Expect path to match
    expect(safePath.path.replaceAll('/', '\\'), path.replaceAll('/', '\\'));

    Directory(path).deleteSync();
  });

  test('SafePath non-existent path cleanup', () {
    // Should not throw even if the target path doesn't exist.
    // Use a unique directory under the system temp folder to avoid touching real drives.
    final Directory baseTempDir =
        Directory.systemTemp.createTempSync('safepath_non_existent_');
    final String path = '${baseTempDir.path}\\non_existent_path_test_12345';
    try {
      SafePath safePath = SafePath(path);
      expect(safePath.path, path);
    } finally {
      // Clean up any directories created by the test.
      final Directory targetDir = Directory(path);
      if (targetDir.existsSync()) {
        targetDir.deleteSync(recursive: true);
      }
      if (baseTempDir.existsSync()) {
        baseTempDir.deleteSync(recursive: true);
      }
    }
  });

  test('SafePath special characters', () {
    // Using the character from the issue: ¤
    String path = '${Directory.current.path}\\test_special_¤_char';
    Directory(path).createSync(recursive: true);

    try {
      SafePath safePath = SafePath(path);
      expect(safePath.path, path);
      expect(Directory(path).existsSync(), true);
    } finally {
      if (Directory(path).existsSync()) {
        Directory(path).deleteSync(recursive: true);
      }
    }
  });

  test('SafePath unicode characters', () {
    // Unicode characters
    String path = '${Directory.current.path}\\test_unicode_😊';
    Directory(path).createSync(recursive: true);

    try {
      SafePath safePath = SafePath(path);
      expect(safePath.path, path);
    } finally {
      if (Directory(path).existsSync()) {
        Directory(path).deleteSync(recursive: true);
      }
    }
  });

  test('SafePath file with special characters', () {
    String folder = '${Directory.current.path}\\test_special_¤_folder';
    Directory(folder).createSync(recursive: true);
    String filePath = '$folder\\test_file.txt';
    File(filePath).writeAsStringSync('test');

    try {
      SafePath safePath = SafePath(filePath);
      expect(safePath.path, filePath);
    } finally {
      if (Directory(folder).existsSync()) {
        Directory(folder).deleteSync(recursive: true);
      }
    }
  });
}
