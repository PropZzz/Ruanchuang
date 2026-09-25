// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:html' as html;

import 'local_persistence.dart';

class WebLocalPersistence implements LocalPersistence {
  static const _key = 'sxzppp_data_v1';
  static const _backupKey = 'sxzppp_data_v1_backup';

  String _primaryKey(String namespace) {
    if (namespace == legacyLocalNamespace) return _key;
    return '${_key}_${encodeLocalPersistenceNamespace(namespace)}';
  }

  String _backupStorageKey(String namespace) {
    if (namespace == legacyLocalNamespace) return _backupKey;
    return '${_primaryKey(namespace)}_backup';
  }

  @override
  Future<bool> exists({String namespace = legacyLocalNamespace}) async {
    final storage = html.window.localStorage;
    final primaryKey = _primaryKey(namespace);
    final backupKey = _backupStorageKey(namespace);
    return storage.containsKey(primaryKey) || storage.containsKey(backupKey);
  }

  @override
  Future<String?> read({String namespace = legacyLocalNamespace}) async {
    final storage = html.window.localStorage;
    final primaryKey = _primaryKey(namespace);
    final backupKey = _backupStorageKey(namespace);
    final primary = storage[primaryKey];
    if (primary != null && primary.trim().isNotEmpty) {
      return primary;
    }
    return storage[backupKey];
  }

  @override
  Future<void> write(
    String content, {
    String namespace = legacyLocalNamespace,
  }) async {
    final storage = html.window.localStorage;
    final primaryKey = _primaryKey(namespace);
    final backupKey = _backupStorageKey(namespace);
    final old = storage[primaryKey];
    if (old != null && old.trim().isNotEmpty) {
      storage[backupKey] = old;
    }
    storage[primaryKey] = content;
  }
}

LocalPersistence createLocalPersistence() => WebLocalPersistence();
