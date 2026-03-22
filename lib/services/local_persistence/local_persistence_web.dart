// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:html' as html;

import 'local_persistence.dart';

class WebLocalPersistence implements LocalPersistence {
  static const _key = 'sxzppp_data_v1';
  static const _backupKey = 'sxzppp_data_v1_backup';

  @override
  Future<bool> exists() async {
    final storage = html.window.localStorage;
    return storage.containsKey(_key) || storage.containsKey(_backupKey);
  }

  @override
  Future<String?> read() async {
    final storage = html.window.localStorage;
    final primary = storage[_key];
    if (primary != null && primary.trim().isNotEmpty) {
      return primary;
    }
    return storage[_backupKey];
  }

  @override
  Future<void> write(String content) async {
    final storage = html.window.localStorage;
    final old = storage[_key];
    if (old != null && old.trim().isNotEmpty) {
      storage[_backupKey] = old;
    }
    storage[_key] = content;
  }
}

LocalPersistence createLocalPersistence() => WebLocalPersistence();
