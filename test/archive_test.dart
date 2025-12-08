import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:wsl2distromanager/api/archive.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('archive_test');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test('ArchiveApi.merge merges files correctly', () async {
    final file1 = File('${tempDir.path}/file1');
    final file2 = File('${tempDir.path}/file2');
    final outFile = File('${tempDir.path}/output');

    // Create dummy files
    // file1 has trailing zeros
    await file1.writeAsBytes([1, 2, 3, 0, 0, 0]);
    // file2 is the last one, so it should be written as is
    await file2.writeAsBytes([4, 5, 6]);

    await ArchiveApi.merge([file1.path, file2.path], outFile.path);

    final bytes = await outFile.readAsBytes();
    // Expected: 1, 2, 3 (from file1, zeros removed) + 4, 5, 6 (from file2)

    expect(bytes, [1, 2, 3, 4, 5, 6]);
  });
}
