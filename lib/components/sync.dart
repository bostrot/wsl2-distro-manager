import 'dart:io';

import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_static/shelf_static.dart';
import 'helpers.dart';

class Sync {
  void startServer(String distroName) {
    // Get path for distro filesystem
    //prefs.setString('Path_' + name, location + 'ext4.vhdx');
    String? distroLocation = prefs.getString('Path_' + distroName) ??
        'C:\\WSL2-Distros\\$distroName';
    if (distroLocation.isEmpty) {
      print('Error: No distro path found for $distroName');
      return;
    }
    // Serve filesystem file
    var handler = createFileHandler(distroLocation + '\\ext4.vhdx',
        contentType: "application/octet-stream");
    io.serve(handler, 'localhost', 8080);
  }
}
