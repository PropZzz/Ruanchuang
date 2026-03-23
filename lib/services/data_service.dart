import '../models/models.dart';

/// Data service interface.
///
/// Design goals:
/// - Local-first persistence (offline-friendly)
/// - Swappable implementations (local/remote/mock)
/// - Stable contract for UI (screens)
abstract class DataService {
  Future<EnergyStatus> getEnergyStatus();
  Future<EmotionState> getEmotionState();
  Future<void> addEmotionCheckIn(EmotionCheckIn checkIn);
  Future<List<EmotionCheckIn>> getEmotionCheckIns(DateTime day);

  Future<List<Goal>> getGoals();
  Future<void> upsertGoal(Goal goal);
  Future<void> deleteGoal(String goalId);

  Future<Task> getCurrentTask();
  Future<List<Task>> getNextTasks();

  Future<List<ScheduleEntry>> getScheduleEntries();
  Future<void> addScheduleEntry(ScheduleEntry entry);
  Future<void> removeScheduleEntry(ScheduleEntry entry);

  Future<List<MicroTask>> getMicroTasks();
  Future<void> addMicroTask(MicroTask task);
  Future<void> removeMicroTask(MicroTask task);
  Future<void> updateMicroTask(MicroTask task);

  Future<List<TeamMember>> getTeamMembers();

  Future<UserProfile> getUserProfile();

  Future<void> setFavoriteDevice(String deviceId);
  Future<String?> getFavoriteDevice();

  // ---------------------------------------------------------------------------
  // App settings persistence
  // ---------------------------------------------------------------------------

  Future<String> getThemeMode();
  Future<void> setThemeMode(String themeMode);
  Future<String> getLocale();
  Future<void> setLocale(String locale);

  // ---------------------------------------------------------------------------
  // Review loop & tuning
  // ---------------------------------------------------------------------------

  Future<void> logTaskEvent(TaskEvent event);
  Future<List<TaskEvent>> getTaskEvents(DateTime from, DateTime to);
  Future<ReviewReport> getWeeklyReport(DateTime weekStart);
  Future<SchedulingTuning> getSchedulingTuning();
  Future<void> setSchedulingTuning(SchedulingTuning tuning);

  // ---------------------------------------------------------------------------
  // Team collaboration
  // ---------------------------------------------------------------------------

  Future<List<TeamMemberCalendar>> getTeamCalendars(DateTime day);

  Future<void> updateTeamSharePermission(
    String memberId,
    TeamSharePermission permission,
  );

  Future<void> bookTeamMeeting(DateTime day, TeamMeetingRequest request);
}
