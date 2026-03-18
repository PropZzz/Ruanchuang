import 'dart:io';

import 'package:flutter/foundation.dart';

class IcsSaveResult {
  final String label;
  final String? path;

  const IcsSaveResult({required this.label, this.path});
}

class IcsFileSaver {
  static Future<IcsSaveResult> save(String ics, {required String fileName}) async {
    if (kIsWeb) {
      // Should be handled by web implementation.
      return const IcsSaveResult(label: 'web');
    }

    final env = Platform.environment;

    String baseDir;
    if (Platform.isWindows) {
      baseDir = env['APPDATA'] ?? env['USERPROFILE'] ?? Directory.current.path;
    } else {
      baseDir = env['HOME'] ?? Directory.current.path;
    }

    final dir = Directory('$baseDir${Platform.pathSeparator}sxzppp${Platform.pathSeparator}exports');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final file = File('${dir.path}${Platform.pathSeparator}$fileName');
    await file.writeAsString(ics, flush: true);

    return IcsSaveResult(label: 'saved', path: file.path);
  }
}
