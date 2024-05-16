import 'dart:io';

import 'package:archive/archive_io.dart';

/// API for archive operations
class ArchiveApi {
  /// Extracts the archive at [archivePath] to [destinationPath]
  static Future<void> extract(
      String archivePath, String destinationPath) async {
    // Extract archive
    final inputStream = InputFileStream(archivePath);
    final extracted = GZipDecoder().decodeBuffer(inputStream);
    // Write to destination
    final outputFile = File(destinationPath);
    outputFile.create(recursive: true);
    await outputFile.writeAsBytes(extracted);
    inputStream.close();
  }

  /// Merge the tar archives at [archivePaths] into [destinationPath]
  /// Trailing zeros are removed from the files.
  static Future<void> merge(
      List<String> archivePaths, String destinationPath) async {
    // Merge archives
    try {
      // remove trailing zeros from the files
      final outputFile = File(destinationPath);
      for (var i = 0; i < archivePaths.length; i++) {
        final fileName = archivePaths[i];
        // Read file as byte stream
        final file = File(fileName);
        final bytes = await file.readAsBytes();
        final length = bytes.length;

        // Last layer
        if (i == archivePaths.length - 1) {
          await outputFile.writeAsBytes(bytes);
          break;
        }

        // Remove trailing zeros
        int lastBytePos = 0;
        for (var i = length - 1; i >= 0; i--) {
          if (bytes[i] != 0) {
            lastBytePos = i;
            break;
          }
        }

        // Write to new file
        await outputFile.writeAsBytes(bytes.sublist(0, lastBytePos + 1));
      }
    } catch (e) {
      throw Exception('Failed to merge archives: $e');
    }
  }

  /// Compress the tar archive at [filePath] to [destinationPath]
  static void compress(String filePath, String destinationPath) {
    // compress tar to gzip
    final inputFileStream = InputFileStream(filePath);
    final outputFileStream = OutputFileStream(destinationPath);
    GZipEncoder().encode(inputFileStream,
        output: outputFileStream, level: Deflate.BEST_SPEED);
    inputFileStream.close();
    outputFileStream.close();
  }
}
