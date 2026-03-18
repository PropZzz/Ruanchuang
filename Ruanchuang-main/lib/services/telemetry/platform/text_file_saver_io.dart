import 'dart:io';

import 'package:flutter/foundation.dart';

class SaveTextResult {
  final String? path;
  final String? error;

  const SaveTextResult({this.path, this.error});
}

class TextFileSaver {
  static Future<SaveTextResult> save(
    String content, {
    required String fileName,
  }) async {
    if (kIsWeb) {
      return const SaveTextResult(error: 'io saver used on web');
    }

    try {
      final env = Platform.environment;
      String baseDir = Directory.current.path;
      if (Platform.isWindows) {
        baseDir = env['TEMP'] ?? env['TMP'] ?? baseDir;
      } else {
        baseDir = env['TMPDIR'] ?? '/tmp';
      }

      final dir = Directory('$baseDir${Platform.pathSeparator}sxzppp${Platform.pathSeparator}exports');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final f = File('${dir.path}${Platform.pathSeparator}$fileName');
      await f.writeAsString(content, flush: true);
      return SaveTextResult(path: f.path);
    } catch (e) {
      return SaveTextResult(error: e.toString());
    }
  }
}