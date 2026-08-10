import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/models.dart';
import 'api_client.dart';
import 'data_service.dart';
import 'remote_data_service.dart';

/// Composite remote service with a local cache and offline fallback.
///
/// Policy:
/// - Reads prefer local unless [preferRemoteReads] is enabled.
/// - Writes commit remotely first; local cache synchronization after a remote
///   commit is best effort and must not invite a duplicate remote write.
/// - A local write is the fallback only when the remote is unavailable.
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

  bool _isRemoteFallbackError(Object error) {
    if (error is RemoteUnavailableException ||
        error is TimeoutException ||
        error is SocketException ||
        error is http.ClientException) {
      return true;
    }

    return error is ApiException &&
        error.statusCode != null &&
        error.statusCode! >= 500;
  }

  Future<T> _read<T>(Future<T> Function(DataService s) fn) async {
    if (preferRemoteReads) {
      try {
        return await fn(remote);
      } catch (error) {
        if (!_isRemoteFallbackError(error)) rethrow;
        return fn(local);
      }
    }
    try {
      return await fn(local);
    } catch (_) {
      try {
        return await fn(remote);
      } catch (error) {
        if (!_isRemoteFallbackError(error)) rethrow;
        return fn(local);
      }
    }
  }

  Future<void> _writeVoid(Future<void> Function(DataService s) fn) async {
    var remoteSucceeded = false;
    try {
      await fn(remote);
      remoteSucceeded = true;
    } catch (error) {
      if (!_isRemoteFallbackError(error)) rethrow;
    }

    try {
      await fn(local);
    } catch (_) {
      if (!remoteSucceeded) rethrow;
    }
  }

  Future<T> _writeValue<T>(Future<T> Function(DataService s) fn) async {
    T? remoteResult;
    var remoteSucceeded = false;
    try {
      remoteResult = await fn(remote);
      remoteSucceeded = true;
    } catch (error) {
      if (!_isRemoteFallbackError(error)) rethrow;
    }

    try {
      final localResult = await fn(local);
      return remoteSucceeded ? remoteResult as T : localResult;
    } catch (_) {
      if (!remoteSucceeded) rethrow;
      return remoteResult as T;
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
      _writeVoid((s) => s.setFavoriteDevice(deviceId));

  @override
  Future<String?> getFavoriteDevice() => _read((s) => s.getFavoriteDevice());

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
  Future<bool> login(String account, String password) =>
      _writeValue((s) => s.login(account, password));

  @override
  Future<bool> registerAccount({
    required String username,
    required String password,
  }) => _writeValue(
    (s) => s.registerAccount(username: username, password: password),
  );

  @override
  Future<void> logout() => _writeVoid((s) => s.logout());
}
