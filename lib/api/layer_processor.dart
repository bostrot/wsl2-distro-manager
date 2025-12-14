import 'dart:async';
import 'dart:io';
import 'package:tar/tar.dart';
import 'package:path/path.dart' as p;

class LayerProcessor {
  /// Merges Docker layers into a single rootfs tarball, handling whiteouts.
  /// [layerPaths] is a list of paths to .tar.gz layer files, ordered from bottom (base) to top.
  /// [outputPath] is the path where the resulting .tar.gz will be written.
  Future<void> mergeLayers(List<String> layerPaths, String outputPath,
      Function(String) onStatus) async {
    final keptFiles = <String, int>{}; // Path -> Layer Index

    onStatus('Scanning layers...');
    // Pass 1: Determine which files to keep
    for (var i = 0; i < layerPaths.length; i++) {
      onStatus('Scanning layer ${i + 1}/${layerPaths.length}...');
      final layerPath = layerPaths[i];
      final file = File(layerPath);
      if (!await file.exists()) continue;

      final reader = TarReader(file.openRead().transform(gzip.decoder));
      try {
        while (await reader.moveNext()) {
          final entry = reader.current;
          final path = entry.name;
          final filename = p.posix.basename(path);
          final dirname = p.posix.dirname(path);

          if (filename.startsWith('.wh.')) {
            if (filename == '.wh..wh..opq') {
              // Opaque whiteout: hide all siblings in this directory from lower layers
              keptFiles.removeWhere((key, value) {
                final keyDir = p.posix.dirname(key);
                return keyDir == dirname && value < i;
              });
            } else {
              // Explicit whiteout
              final realFilename = filename.substring(4);
              final realPath =
                  p.posix.normalize(p.posix.join(dirname, realFilename));
              keptFiles.remove(realPath);
            }
          } else {
            // Normal file/directory
            final normalizedPath = p.posix.normalize(path);
            keptFiles[normalizedPath] = i;
          }
        }
      } finally {
        await reader.cancel();
      }
    }

    onStatus('Writing rootfs...');
    // Pass 2: Write the output tar
    final outFile = File(outputPath);
    if (await outFile.exists()) {
      await outFile.delete();
    }

    Stream<TarEntry> streamLayers() async* {
      for (var i = 0; i < layerPaths.length; i++) {
        onStatus('Merging layer ${i + 1}/${layerPaths.length}...');
        final layerPath = layerPaths[i];
        final file = File(layerPath);
        if (!await file.exists()) continue;

        final reader = TarReader(file.openRead().transform(gzip.decoder));
        try {
          while (await reader.moveNext()) {
            final entry = reader.current;
            final path = entry.name;
            final filename = p.posix.basename(path);

            // Skip whiteout files themselves in the output
            if (filename.startsWith('.wh.')) {
              continue;
            }

            final normalizedPath = p.posix.normalize(path);

            if (keptFiles[normalizedPath] == i) {
              // We need to wait for the entry to be fully consumed by the writer
              // before moving the reader to the next entry.
              final completer = Completer();
              final trackedStream = entry.contents.transform(
                  StreamTransformer<List<int>, List<int>>.fromHandlers(
                handleData: (data, sink) => sink.add(data),
                handleError: (error, stack, sink) =>
                    sink.addError(error, stack),
                handleDone: (sink) {
                  sink.close();
                  completer.complete();
                },
              ));

              yield TarEntry(entry.header, trackedStream);
              await completer.future;
            }
          }
        } finally {
          await reader.cancel();
        }
      }
    }

    await streamLayers()
        .transform(tarWriter)
        .transform(gzip.encoder)
        .pipe(outFile.openWrite());
  }
}
