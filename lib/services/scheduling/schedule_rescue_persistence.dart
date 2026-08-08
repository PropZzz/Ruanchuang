import '../../models/models.dart';

typedef ScheduleEntryWriter = Future<void> Function(ScheduleEntry entry);

class ScheduleRescuePersistence {
  final ScheduleEntryWriter upsert;
  final ScheduleEntryWriter remove;

  const ScheduleRescuePersistence({required this.upsert, required this.remove});

  Future<void> apply({
    required List<ScheduleEntry> before,
    required List<ScheduleEntry> after,
  }) async {
    try {
      await _synchronize(from: before, to: after);
    } catch (error, stackTrace) {
      try {
        await _synchronize(from: after, to: before);
      } catch (_) {
        // Preserve the original synchronization failure.
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> _synchronize({
    required List<ScheduleEntry> from,
    required List<ScheduleEntry> to,
  }) async {
    final fromById = _entriesById(from);
    final toById = _entriesById(to);

    for (final entry in toById.values) {
      await upsert(entry);
    }
    for (final entry in fromById.values) {
      if (!toById.containsKey(entry.id)) {
        await remove(entry);
      }
    }
  }

  Map<String, ScheduleEntry> _entriesById(List<ScheduleEntry> entries) => {
    for (final entry in entries)
      if (entry.id != null && entry.id!.isNotEmpty) entry.id!: entry,
  };
}
