import '../models/models.dart';
import 'data_service.dart';
import 'service_result.dart';

/// Composite remote service with a local cache and offline fallback.
///
/// Policy:
/// - Reads prefer the remote source unless it is unavailable.
/// - Writes commit remotely first; local cache synchronization after a remote
///   commit is best effort and must not invite a duplicate remote write.
/// - A local write is the fallback only when the remote is unavailable.
class CompositeDataService implements DataService {
  final DataService local;
  final DataService remote;

  /// If true, reads attempt remote first, then local fallback.
  bool preferRemoteReads;
  bool _guestOnly = false;
  bool _localCacheReady = true;

  CompositeDataService({
    required this.local,
    required this.remote,
    this.preferRemoteReads = true,
  });

  /// Keep unauthenticated sessions on their isolated local cache.
  @override
  Future<void> startGuestSession() async {
    await local.startGuestSession();
    _guestOnly = true;
    _localCacheReady = true;
    try {
      await remote.startGuestSession();
    } catch (_) {
      // Remote session reset is best effort before the first sign-in.
    }
  }

  Future<T> _read<T>(Future<T> Function(DataService s) fn) async {
    return (await readResult(fn)).unwrap();
  }

  /// Run one data read. The callback must not perform writes/session commands.
  Future<ServiceResult<T>> readResult<T>(
    Future<T> Function(DataService) fn,
  ) async {
    if (_guestOnly) return _localResult(fn);
    if (_localCacheReady && !preferRemoteReads) {
      final result = await _localResult(fn);
      if (result is ServiceSuccess<T>) return result;
    }
    try {
      return ServiceSuccess(await fn(remote), source: ServiceSource.remote);
    } catch (error, stack) {
      final problem = serviceProblem(
        error,
        stack,
        ServiceSource.remote,
        write: false,
      );
      if (!allowsLocalFallback(error) || !_localCacheReady) {
        return ServiceFailure(problem);
      }
      return _localResult(fn, fallback: problem);
    }
  }

  Future<void> _writeVoid(Future<void> Function(DataService s) fn) async {
    (await writeResult(fn)).unwrap();
  }

  /// Run one idempotent data write with the same payload on both adapters.
  /// Multi-step workflows and auth/logout are not transactions through this API.
  Future<ServiceResult<void>> writeResult(
    Future<void> Function(DataService) fn,
  ) async {
    if (_guestOnly) return _localResult(fn, write: true);
    try {
      await fn(remote);
    } catch (error, stack) {
      final problem = serviceProblem(
        error,
        stack,
        ServiceSource.remote,
        write: true,
      );
      if (!allowsLocalFallback(error) || !_localCacheReady)
        return ServiceFailure(problem);
      return _localResult(fn, write: true, fallback: problem);
    }
    try {
      await fn(local);
      return const ServiceSuccess(null, source: ServiceSource.remote);
    } catch (error, stack) {
      _localCacheReady = false;
      return ServiceSuccess(
        null,
        source: ServiceSource.remote,
        cacheWarning: serviceProblem(
          error,
          stack,
          ServiceSource.local,
          write: true,
        ),
      );
    }
  }

  Future<ServiceResult<T>> _localResult<T>(
    Future<T> Function(DataService) fn, {
    bool write = false,
    ServiceProblem? fallback,
  }) async {
    try {
      return ServiceSuccess(
        await fn(local),
        source: ServiceSource.local,
        fallbackCause: fallback,
        remoteCommitUncertain: write && fallback != null,
      );
    } catch (error, stack) {
      return ServiceFailure(
        serviceProblem(error, stack, ServiceSource.local, write: write),
        fallbackCause: fallback,
      );
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
      _writeVoid((s) => s.addEmotionCheckIn(checkIn));

  @override
  Future<List<EmotionCheckIn>> getEmotionCheckIns(DateTime day) =>
      _read((s) => s.getEmotionCheckIns(day));

  @override
  Future<List<Goal>> getGoals() => _read((s) => s.getGoals());

  @override
  Future<void> upsertGoal(Goal goal) => _writeVoid((s) => s.upsertGoal(goal));

  @override
  Future<void> deleteGoal(String goalId) =>
      _writeVoid((s) => s.deleteGoal(goalId));

  @override
  Future<Task> getCurrentTask() => _read((s) => s.getCurrentTask());

  @override
  Future<List<Task>> getNextTasks() => _read((s) => s.getNextTasks());

  @override
  Future<List<ScheduleEntry>> getScheduleEntries() =>
      _read((s) => s.getScheduleEntries());

  @override
  Future<void> addScheduleEntry(ScheduleEntry entry) =>
      _writeVoid((s) => s.addScheduleEntry(entry));

  @override
  Future<void> removeScheduleEntry(ScheduleEntry entry) =>
      _writeVoid((s) => s.removeScheduleEntry(entry));

  @override
  Future<List<MicroTask>> getMicroTasks() => _read((s) => s.getMicroTasks());

  @override
  Future<void> addMicroTask(MicroTask task) =>
      _writeVoid((s) => s.addMicroTask(task));

  @override
  Future<void> removeMicroTask(MicroTask task) =>
      _writeVoid((s) => s.removeMicroTask(task));

  @override
  Future<void> updateMicroTask(MicroTask task) =>
      _writeVoid((s) => s.updateMicroTask(task));

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
  Future<void> logTaskEvent(TaskEvent event) =>
      _writeVoid((s) => s.logTaskEvent(event));

  @override
  Future<void> upsertTaskEvents(List<TaskEvent> events) =>
      _writeVoid((s) => s.upsertTaskEvents(events));

  @override
  Future<List<TaskEvent>> getTaskEvents(DateTime from, DateTime to) =>
      _read((s) => s.getTaskEvents(from, to));

  @override
  Future<ReviewReport> getWeeklyReport(DateTime weekStart) =>
      _read((s) => s.getWeeklyReport(weekStart));

  @override
  Future<SchedulingTuning> getSchedulingTuning() =>
      _read((s) => s.getSchedulingTuning());

  @override
  Future<void> setSchedulingTuning(SchedulingTuning tuning) =>
      _writeVoid((s) => s.setSchedulingTuning(tuning));

  @override
  Future<List<TeamMemberCalendar>> getTeamCalendars(DateTime day) =>
      _read((s) => s.getTeamCalendars(day));

  @override
  Future<void> upsertTeamMember(TeamMemberCalendar member) =>
      _writeVoid((s) => s.upsertTeamMember(member));

  @override
  Future<void> deleteTeamMember(String memberId) =>
      _writeVoid((s) => s.deleteTeamMember(memberId));

  @override
  Future<void> updateTeamSharePermission(
    String memberId,
    TeamSharePermission permission,
  ) => _writeVoid((s) => s.updateTeamSharePermission(memberId, permission));

  @override
  Future<void> bookTeamMeeting(DateTime day, TeamMeetingRequest request) =>
      _writeVoid((s) => s.bookTeamMeeting(day, request));

  @override
  Future<String> getThemeMode() => _read((s) => s.getThemeMode());

  @override
  Future<void> setThemeMode(String themeMode) =>
      _writeVoid((s) => s.setThemeMode(themeMode));

  @override
  Future<String> getLocale() => _read((s) => s.getLocale());

  @override
  Future<void> setLocale(String locale) =>
      _writeVoid((s) => s.setLocale(locale));

  // --- 重点：新增的认证相关路由 ---

  @override
  Future<UserAccount?> getCurrentUser() => _read((s) => s.getCurrentUser());

  @override
  Future<bool> login(String account, String password) async {
    final result = await remote.login(account, password);
    if (!result) return false;

    _guestOnly = false;
    _localCacheReady = false;
    try {
      _localCacheReady = await local.login(account, password);
    } catch (_) {
      // Local cache synchronization is best effort after remote auth.
    }
    return result;
  }

  @override
  Future<bool> registerAccount({
    required String username,
    required String displayName,
    required String password,
  }) async {
    final result = await remote.registerAccount(
      username: username,
      displayName: displayName,
      password: password,
    );
    if (!result) return false;

    _guestOnly = false;
    _localCacheReady = false;
    try {
      _localCacheReady = await local.registerAccount(
        username: username,
        displayName: displayName,
        password: password,
      );
    } catch (_) {
      // Local cache synchronization is best effort after remote auth.
    }
    return result;
  }

  @override
  Future<void> logout() async {
    Object? remoteError;
    StackTrace? remoteStack;
    _localCacheReady = false;
    if (!_guestOnly) {
      try {
        await remote.logout();
      } catch (error, stackTrace) {
        remoteError = error;
        remoteStack = stackTrace;
      }
    }
    await local.logout();
    _guestOnly = true;
    _localCacheReady = true;
    if (remoteError != null) {
      Error.throwWithStackTrace(remoteError, remoteStack!);
    }
  }
}
