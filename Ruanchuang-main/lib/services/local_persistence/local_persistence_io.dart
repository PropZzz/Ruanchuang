import 'dart:io';

import 'local_persistence.dart';

class IoLocalPersistence implements LocalPersistence {
  static const _dirName = 'sxzppp';
  static const _fileName = 'sxzppp_data_v1.json';

  String _baseDirPath() {
    final env = Platform.environment;

    if (Platform.isWindows) {
      final appData = env['APPDATA'];
      if (appData != null && appData.isNotEmpty) return appData;
      final userProfile = env['USERPROFILE'];
      if (userProfile != null && userProfile.isNotEmpty) {
        return '$userProfile\\AppData\\Roaming';
      }
    }

    final home = env['HOME'];
    if (home != null && home.isNotEmpty) return home;

    // Last-resort fallback: still deterministic for the current working dir.
    return Directory.current.path;
  }

  Future<File> _file() async {
    final base = _baseDirPath();
    final dir = Directory('$base${Platform.pathSeparator}$_dirName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}${Platform.pathSeparator}$_fileName');
  }

  @override
  Future<bool> exists() async {
    final f = await _file();
    return f.exists();
  }

  @override
  Future<String?> read() async {
    final f = await _file();
    if (!await f.exists()) return null;
    return f.readAsString();
  }

  @override
  Future<void> write(String content) async {
    final f = await _file();
    await f.writeAsString(content, flush: true);
  }
}

LocalPersistence createLocalPersistence() => IoLocalPersistence();
