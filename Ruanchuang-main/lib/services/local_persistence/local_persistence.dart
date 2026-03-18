/// Minimal persistence primitive for LocalDataService.
///
/// Implemented with File on IO platforms and localStorage on Web.
abstract class LocalPersistence {
  Future<bool> exists();
  Future<String?> read();
  Future<void> write(String content);
}


