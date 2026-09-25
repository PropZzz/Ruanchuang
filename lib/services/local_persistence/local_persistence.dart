import 'dart:convert';

const String legacyLocalNamespace = 'legacy';

String encodeLocalPersistenceNamespace(String namespace) {
  return base64Url.encode(utf8.encode(namespace)).replaceAll('=', '');
}

/// Minimal persistence primitive for LocalDataService.
///
/// Implemented with File on IO platforms and localStorage on Web.
abstract class LocalPersistence {
  Future<bool> exists({String namespace = legacyLocalNamespace});
  Future<String?> read({String namespace = legacyLocalNamespace});
  Future<void> write(String content, {String namespace = legacyLocalNamespace});
}

/// Tiny test seam for LocalDataService without touching runtime storage.
class InMemoryLocalPersistence implements LocalPersistence {
  final Map<String, String> _contentByNamespace = <String, String>{};

  String _storageKey(String namespace) => namespace == legacyLocalNamespace
      ? legacyLocalNamespace
      : encodeLocalPersistenceNamespace(namespace);

  @override
  Future<bool> exists({String namespace = legacyLocalNamespace}) async =>
      _contentByNamespace.containsKey(_storageKey(namespace));

  @override
  Future<String?> read({String namespace = legacyLocalNamespace}) async =>
      _contentByNamespace[_storageKey(namespace)];

  @override
  Future<void> write(
    String content, {
    String namespace = legacyLocalNamespace,
  }) async {
    _contentByNamespace[_storageKey(namespace)] = content;
  }
}
