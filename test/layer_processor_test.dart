import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:tar/tar.dart';
import 'package:test/test.dart';
import 'package:wsl2distromanager/api/layer_processor.dart';

void main() {
  late Directory tempDir;
  late LayerProcessor processor;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('layer_processor_test');
    processor = LayerProcessor();
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  Future<void> createTar(String path, Map<String, String> entries) async {
    final file = File(path);
    final sink = file.openWrite();

    final stream = Stream.fromIterable(entries.entries.map((e) {
      return TarEntry.data(
        TarHeader(
          name: e.key,
          mode: int.parse('644', radix: 8),
        ),
        e.value.codeUnits,
      );
    }));

    await stream
        .cast<TarEntry>()
        .transform(tarWriter)
        .transform(gzip.encoder)
        .pipe(sink);
  }

  Future<Map<String, String>> readTar(String path) async {
    final file = File(path);
    final reader = TarReader(file.openRead().transform(gzip.decoder));
    final result = <String, String>{};

    while (await reader.moveNext()) {
      final entry = reader.current;
      final content =
          await entry.contents.transform(SystemEncoding().decoder).join();
      result[entry.name] = content;
    }
    await reader.cancel();
    return result;
  }

  test('merges simple layers', () async {
    final layer1Path = p.join(tempDir.path, 'layer1.tar.gz');
    final layer2Path = p.join(tempDir.path, 'layer2.tar.gz');
    final outputPath = p.join(tempDir.path, 'output.tar.gz');

    await createTar(layer1Path, {'file1.txt': 'content1'});
    await createTar(layer2Path, {'file2.txt': 'content2'});

    await processor.mergeLayers(
      [layer1Path, layer2Path],
      outputPath,
      (_) {},
    );

    final result = await readTar(outputPath);
    expect(result, hasLength(2));
    expect(result['file1.txt'], 'content1');
    expect(result['file2.txt'], 'content2');
  });

  test('upper layer overwrites lower layer', () async {
    final layer1Path = p.join(tempDir.path, 'layer1.tar.gz');
    final layer2Path = p.join(tempDir.path, 'layer2.tar.gz');
    final outputPath = p.join(tempDir.path, 'output.tar.gz');

    await createTar(layer1Path, {'file1.txt': 'v1'});
    await createTar(layer2Path, {'file1.txt': 'v2'});

    await processor.mergeLayers(
      [layer1Path, layer2Path],
      outputPath,
      (_) {},
    );

    final result = await readTar(outputPath);
    expect(result, hasLength(1));
    expect(result['file1.txt'], 'v2');
  });

  test('handles whiteout files', () async {
    final layer1Path = p.join(tempDir.path, 'layer1.tar.gz');
    final layer2Path = p.join(tempDir.path, 'layer2.tar.gz');
    final outputPath = p.join(tempDir.path, 'output.tar.gz');

    await createTar(layer1Path, {
      'keep.txt': 'keep',
      'delete.txt': 'delete',
    });
    await createTar(layer2Path, {
      '.wh.delete.txt': '',
    });

    await processor.mergeLayers(
      [layer1Path, layer2Path],
      outputPath,
      (_) {},
    );

    final result = await readTar(outputPath);
    expect(result, hasLength(1));
    expect(result['keep.txt'], 'keep');
    expect(result.containsKey('delete.txt'), isFalse);
    expect(result.containsKey('.wh.delete.txt'), isFalse);
  });

  test('handles opaque directories', () async {
    final layer1Path = p.join(tempDir.path, 'layer1.tar.gz');
    final layer2Path = p.join(tempDir.path, 'layer2.tar.gz');
    final outputPath = p.join(tempDir.path, 'output.tar.gz');

    await createTar(layer1Path, {
      'dir/file1.txt': 'v1',
      'dir/file2.txt': 'v1',
      'other/file3.txt': 'v1',
    });
    await createTar(layer2Path, {
      'dir/.wh..wh..opq': '',
      'dir/file1.txt': 'v2',
    });

    await processor.mergeLayers(
      [layer1Path, layer2Path],
      outputPath,
      (_) {},
    );

    final result = await readTar(outputPath);
    expect(result.containsKey('other/file3.txt'), isTrue);
    expect(result['dir/file1.txt'], 'v2');
    expect(result.containsKey('dir/file2.txt'), isFalse);
    expect(result.containsKey('dir/.wh..wh..opq'), isFalse);
  });

  test('reports progress', () async {
    final layer1Path = p.join(tempDir.path, 'layer1.tar.gz');
    final layer2Path = p.join(tempDir.path, 'layer2.tar.gz');
    final outputPath = p.join(tempDir.path, 'output.tar.gz');

    await createTar(layer1Path, {'file1.txt': 'content1'});
    await createTar(layer2Path, {'file2.txt': 'content2'});

    final messages = <String>[];
    await processor.mergeLayers(
      [layer1Path, layer2Path],
      outputPath,
      (msg) => messages.add(msg),
    );

    expect(messages, contains('Scanning layers...'));
    expect(messages, contains('Scanning layer 1/2...'));
    expect(messages, contains('Scanning layer 2/2...'));
    expect(messages, contains('Writing rootfs...'));
    expect(messages, contains('Merging layer 1/2...'));
    expect(messages, contains('Merging layer 2/2...'));
  });
}
