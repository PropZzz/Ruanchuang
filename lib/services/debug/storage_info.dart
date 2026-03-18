class StorageInfo {
  final bool exists;
  final int bytes;
  final String backend;

  const StorageInfo({
    required this.exists,
    required this.bytes,
    required this.backend,
  });
}