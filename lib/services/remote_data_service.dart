import '../models/models.dart';
import 'data_service.dart';

class RemoteDataException implements Exception {
  final String message;
  RemoteDataException(this.message);

  @override
  String toString() => 'RemoteDataException: $message';
}

/// Remote data service placeholder.
///
/// This is intentionally a stub: no network calls are made yet.
/// When we integrate a backend/AI, we keep the UI contract stable.
class RemoteDataService implements DataService {
  RemoteDataService._();
  static final RemoteDataService instance = RemoteDataService._();

  Never _unavailable() {
    throw RemoteDataException('Remote data service is not configured.');
  }

  @override
  Future<EnergyStatus> getEnergyStatus() async => Future.error(_unavailable());

  @override
  Future<EmotionState> getEmotionState() async => Future.error(_unavailable());

  @override
  Future<void> addEmotionCheckIn(EmotionCheckIn checkIn) async =>
      Future.error(_unavailable());

  @override
  Future<List<EmotionCheckIn>> getEmotionCheckIns(DateTime day) async =>
      Future.error(_unavailable());

  @override
  Future<List<Goal>> getGoals() async => Future.error(_unavailable());

  @override
  Future<void> upsertGoal(Goal goal) async => Future.error(_unavailable());

  @override
  Future<void> deleteGoal(String goalId) async => Future.error(_unavailable());

  @override
  Future<Task> getCurrentTask() async => Future.error(_unavailable());

  @override
  Future<List<Task>> getNextTasks() async => Future.error(_unavailable());

  @override
  Future<List<ScheduleEntry>> getScheduleEntries() async =>
      Future.error(_unavailable());

  @override
  Future<void> addScheduleEntry(ScheduleEntry entry) async =>
      Future.error(_unavailable());

  @override
  Future<void> removeScheduleEntry(ScheduleEntry entry) async =>
      Future.error(_unavailable());

  @override
  Future<List<MicroTask>> getMicroTasks() async => Future.error(_unavailable());

  @override
  Future<void> addMicroTask(MicroTask task) async => Future.error(_unavailable());

  @override
  Future<void> removeMicroTask(MicroTask task) async =>
      Future.error(_unavailable());

  @override
  Future<void> updateMicroTask(MicroTask task) async =>
      Future.error(_unavailable());

  @override
  Future<List<TeamMember>> getTeamMembers() async => Future.error(_unavailable());

  @override
  Future<UserProfile> getUserProfile() async => Future.error(_unavailable());

  @override
  Future<void> logTaskEvent(TaskEvent event) async => Future.error(_unavailable());

  @override
  Future<List<TaskEvent>> getTaskEvents(DateTime from, DateTime to) async =>
      Future.error(_unavailable());

  @override
  Future<ReviewReport> getWeeklyReport(DateTime weekStart) async =>
      Future.error(_unavailable());

  @override
  Future<SchedulingTuning> getSchedulingTuning() async =>
      Future.error(_unavailable());

  @override
  Future<String?> getFavoriteDevice() async => Future.error(_unavailable());

  @override
  Future<void> setFavoriteDevice(String deviceId) async =>
      Future.error(_unavailable());

  @override
  Future<List<TeamMemberCalendar>> getTeamCalendars(DateTime day) async =>
      Future.error(_unavailable());

  @override
  Future<void> bookTeamMeeting(DateTime day, TeamMeetingRequest request) async =>
      Future.error(_unavailable());

  @override
  Future<void> setSchedulingTuning(SchedulingTuning tuning) async =>
      Future.error(_unavailable());
}
