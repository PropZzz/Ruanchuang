import 'dart:io';

class IcsSaveResult {
  final String label;
  final String? path;

  const IcsSaveResult({required this.label, this.path});
}

class IcsFileSaver {
  static Future<IcsSaveResult> save(
    String ics, {
    required String fileName,
  }) async {
    final baseDir = _resolveBaseDir();
    final dir = Directory('$baseDir${Platform.pathSeparator}exports');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final file = File('${dir.path}${Platform.pathSeparator}$fileName');
    await file.writeAsString(ics, flush: true);

    return IcsSaveResult(label: 'saved', path: file.path);
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
      return env['APPDATA'] ?? env['USERPROFILE'] ?? Directory.current.path;
    }

    if (Platform.isMacOS || Platform.isLinux) {
      final env = Platform.environment;
      return env['HOME'] ?? Directory.current.path;
    }

    return Directory.systemTemp.path;
  }
}
