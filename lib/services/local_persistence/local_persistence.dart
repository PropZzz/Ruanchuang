/// Minimal persistence primitive for LocalDataService.
///
/// Implemented with File on IO platforms and localStorage on Web.
abstract class LocalPersistence {
  Future<bool> exists();
  Future<String?> read();
  Future<void> write(String content);
}

/// Tiny test seam for LocalDataService without touching runtime storage.
class InMemoryLocalPersistence implements LocalPersistence {
  String? _content;

  @override
  Future<bool> exists() async => _content != null;

  @override
  Future<String?> read() async => _content;

  @override
  Future<void> write(String content) async {
    _content = content;
  }
}


