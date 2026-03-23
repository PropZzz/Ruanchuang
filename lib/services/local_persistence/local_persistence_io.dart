import 'dart:io';

import 'local_persistence.dart';

class IoLocalPersistence implements LocalPersistence {
  static const _dirName = 'sxzppp';
  static const _fileName = 'sxzppp_data_v1.json';
  static const _backupFileName = 'sxzppp_data_v1.bak.json';

  String? _cachedBaseDir;

  Future<String> _baseDirPath() async {
    if (_cachedBaseDir != null) return _cachedBaseDir!;

    String basePath;

    if (Platform.isAndroid || Platform.isIOS) {
      try {
        basePath = Directory.systemTemp.parent.path;
      } catch (_) {
        basePath = Directory.systemTemp.path;
      }
    } else if (Platform.isWindows) {
      final env = Platform.environment;
      final appData = env['APPDATA'];
      if (appData != null && appData.isNotEmpty) {
        basePath = appData;
      } else {
        final userProfile = env['USERPROFILE'];
        if (userProfile != null && userProfile.isNotEmpty) {
          basePath = '$userProfile\\AppData\\Roaming';
        } else {
          basePath = Directory.current.path;
        }
      }
    } else if (Platform.isMacOS || Platform.isLinux) {
      final env = Platform.environment;
      final home = env['HOME'];
      if (home != null && home.isNotEmpty) {
        basePath = home;
      } else {
        basePath = Directory.current.path;
      }
    } else {
      basePath = Directory.current.path;
    }

    _cachedBaseDir = basePath;
    return basePath;
  }

  Future<File> _file() async {
    final base = await _baseDirPath();
    final dir = Directory('$base${Platform.pathSeparator}$_dirName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}${Platform.pathSeparator}$_fileName');
  }

  Future<File> _backupFile() async {
    final f = await _file();
    return File('${f.parent.path}${Platform.pathSeparator}$_backupFileName');
  }

  @override
  Future<bool> exists() async {
    final f = await _file();
    if (await f.exists()) return true;
    final backup = await _backupFile();
    return backup.exists();
  }

  @override
  Future<String?> read() async {
    final f = await _file();
    if (await f.exists()) {
      final primary = await f.readAsString();
      if (primary.trim().isNotEmpty) {
        return primary;
      }
    }

    final backup = await _backupFile();
    if (!await backup.exists()) return null;
    return backup.readAsString();
  }

  @override
  Future<void> write(String content) async {
    final f = await _file();
    final backup = await _backupFile();
    final tmp = File('${f.path}.tmp');

    await tmp.writeAsString(content, flush: true);

    if (await f.exists()) {
      if (await backup.exists()) {
        await backup.delete();
      }
      await f.copy(backup.path);
      await f.delete();
    }

    try {
      await tmp.rename(f.path);
    } catch (_) {
      if (await f.exists()) {
        await f.delete();
      }
      await tmp.copy(f.path);
      if (await tmp.exists()) {
        await tmp.delete();
      }
    }
  }
}

LocalPersistence createLocalPersistence() => IoLocalPersistence();
