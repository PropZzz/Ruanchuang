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
      final baseDir = _resolveBaseDir();
      final dir = Directory('$baseDir${Platform.pathSeparator}exports');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final file = File('${dir.path}${Platform.pathSeparator}$fileName');
      await file.writeAsString(content, flush: true);
      return SaveTextResult(path: file.path);
    } catch (e) {
      return SaveTextResult(error: e.toString());
    }
  }

  static String _resolveBaseDir() {
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        return Directory.systemTemp.parent.path;
      } catch (_) {
        return Directory.systemTemp.path;
      }
    }

    if (Platform.isWindows) {
      final env = Platform.environment;
      return env['APPDATA'] ??
          env['USERPROFILE'] ??
          Directory.current.path;
    }

    if (Platform.isMacOS || Platform.isLinux) {
      final env = Platform.environment;
      return env['HOME'] ?? Directory.current.path;
    }

    return Directory.systemTemp.path;
  }
}
