import 'dart:io';

/// Safe path handling.
class SafePath {
  String _path;
  bool isFile = false;

  /// Create a safe path from [_path].
  /// It will be created as a folder if it does not exist.
  SafePath(this._path) {
    // Check if path exists and see if it is a file or a folder
    Directory dir = Directory(_path);
    File file = File(_path);
    if (!dir.existsSync()) {
      if (file.existsSync()) {
        isFile = true;
      } else {
        // Create path
        dir.createSync(recursive: true);
      }
    }

    // Set path
    if (isFile) {
      _path = file.path;
    } else {
      _path = dir.path;
    }
  }

  /// Get the path.
  String get path => _path;

  /// Get the parent path.
  /// If it is a file, the parent folder will be returned.
  String get parent {
    if (isFile) {
      return File(_path).parent.path;
    } else {
      return Directory(_path).parent.path;
    }
  }

  /// Change directory to parent folder.
  /// If it is a file, the parent folder will be returned.
  /// Returns the new path.
  void cdUp() {
    if (isFile) {
      // Do nothing
    } else {
      _path = Directory(_path).parent.path;
    }
  }

  /// Get a file path from [name] if it is a folder.
  /// If it is a file, the file path will be returned.
  String file(String name) {
    if (isFile) {
      return _path;
    } else {
      return File('$_path\\$name').path;
    }
  }

  /// Change directory to subfolder [name].
  /// It will be created if it does not exist.
  /// If it is a file, the parent folder will be returned.
  /// Returns the new path.
  void cd(String name) {
    if (isFile) {
      // Do nothing
    } else {
      String path = '$_path\\$name';
      // Check if path exists
      Directory dir = Directory(path);
      if (!dir.existsSync()) {
        // Create path
        dir.createSync(recursive: true);
      }
      _path = dir.path;
    }
  }
}
