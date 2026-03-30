import '../models/models.dart';
import 'data_service.dart';

/// Local-first composite.
///
/// Policy:
/// - All writes go to local.
/// - Reads prefer local.
/// - Remote is a placeholder for future integration.
class CompositeDataService implements DataService {
  final DataService local;
  final DataService remote;

  /// If true, reads attempt remote first, then local fallback.
  bool preferRemoteReads;

  CompositeDataService({
    required this.local,
    required this.remote,
    this.preferRemoteReads = false,
  });

  Future<T> _read<T>(Future<T> Function(DataService s) fn) async {
    if (preferRemoteReads) {
      try {
        return await fn(remote);
      } catch (_) {
        return fn(local);
      }
    }
    try {
      return await fn(local);
    } catch (_) {
      return fn(remote);
    }
  }

  @override
  Future<EmotionType> getCurrentEmotion() =>
      _read((s) => s.getCurrentEmotion());

  @override
  Future<EnergyStatus> getEnergyStatus() => _read((s) => s.getEnergyStatus());

  @override
  Future<EmotionState> getEmotionState() => _read((s) => s.getEmotionState());

  @override
  Future<void> addEmotionCheckIn(EmotionCheckIn checkIn) =>
      local.addEmotionCheckIn(checkIn);

  @override
  Future<List<EmotionCheckIn>> getEmotionCheckIns(DateTime day) =>
      _read((s) => s.getEmotionCheckIns(day));

  @override
  Future<List<Goal>> getGoals() => _read((s) => s.getGoals());

  @override
  Future<void> upsertGoal(Goal goal) => local.upsertGoal(goal);

  @override
  Future<void> deleteGoal(String goalId) => local.deleteGoal(goalId);

  @override
  Future<Task> getCurrentTask() => _read((s) => s.getCurrentTask());

  @override
  Future<List<Task>> getNextTasks() => _read((s) => s.getNextTasks());

  @override
  Future<List<ScheduleEntry>> getScheduleEntries() =>
      _read((s) => s.getScheduleEntries());

  @override
  Future<void> addScheduleEntry(ScheduleEntry entry) =>
      local.addScheduleEntry(entry);

  @override
  Future<void> removeScheduleEntry(ScheduleEntry entry) =>
      local.removeScheduleEntry(entry);

  @override
  Future<List<MicroTask>> getMicroTasks() => _read((s) => s.getMicroTasks());

  @override
  Future<void> addMicroTask(MicroTask task) => local.addMicroTask(task);

  @override
  Future<void> removeMicroTask(MicroTask task) => local.removeMicroTask(task);

  @override
  Future<void> updateMicroTask(MicroTask task) => local.updateMicroTask(task);

  @override
  Future<List<TeamMember>> getTeamMembers() => _read((s) => s.getTeamMembers());

  @override
  Future<UserProfile> getUserProfile() => _read((s) => s.getUserProfile());

  @override
  Future<void> setFavoriteDevice(String deviceId) =>
      local.setFavoriteDevice(deviceId);

  @override
  Future<String?> getFavoriteDevice() => local.getFavoriteDevice();

  @override
  Future<void> logTaskEvent(TaskEvent event) => local.logTaskEvent(event);

  @override
  Future<List<TaskEvent>> getTaskEvents(DateTime from, DateTime to) =>
      _read((s) => s.getTaskEvents(from, to));

  @override
  Future<ReviewReport> getWeeklyReport(DateTime weekStart) =>
      local.getWeeklyReport(weekStart);

  @override
  Future<SchedulingTuning> getSchedulingTuning() =>
      _read((s) => s.getSchedulingTuning());

  @override
  Future<void> setSchedulingTuning(SchedulingTuning tuning) =>
      local.setSchedulingTuning(tuning);

  @override
  Future<List<TeamMemberCalendar>> getTeamCalendars(DateTime day) =>
      _read((s) => s.getTeamCalendars(day));

  @override
  Future<void> updateTeamSharePermission(
    String memberId,
    TeamSharePermission permission,
  ) => local.updateTeamSharePermission(memberId, permission);

  @override
  Future<void> bookTeamMeeting(DateTime day, TeamMeetingRequest request) =>
      local.bookTeamMeeting(day, request);

  @override
  Future<String> getThemeMode() => local.getThemeMode();

  @override
  Future<void> setThemeMode(String themeMode) => local.setThemeMode(themeMode);

  @override
  Future<String> getLocale() => local.getLocale();

  @override
  Future<void> setLocale(String locale) => local.setLocale(locale);

  // --- 重点：新增的认证相关路由 ---

  @override
  Future<UserAccount?> getCurrentUser() => local.getCurrentUser();

  @override
  Future<bool> login(String account, String password) => local.login(account, password);

  @override
  Future<bool> registerAccount({required String username, required String password}) =>
      local.registerAccount(username: username, password: password);

  @override
  Future<void> logout() => local.logout();
}