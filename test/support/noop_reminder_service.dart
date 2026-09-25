import 'package:shixuzhipei/models/models.dart';
import 'package:shixuzhipei/services/reminders/reminder_service.dart';

class NoopReminderService extends ReminderService {
  @override
  Future<void> rescheduleDay({
    required DateTime day,
    required List<ScheduleEntry> entries,
  }) async {}

  @override
  Future<void> scheduleEntry({
    required DateTime day,
    required ScheduleEntry entry,
    DateTime? now,
  }) async {}
}
