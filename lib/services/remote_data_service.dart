import '../models/models.dart';
import 'api_client.dart';
import 'data_service.dart';

class RemoteDataException implements Exception {
  final String message;
  RemoteDataException(this.message);

  @override
  String toString() => 'RemoteDataException: $message';
}

class RemoteUnavailableException extends RemoteDataException {
  RemoteUnavailableException(super.message);
}

class RemoteDataService implements DataService {
  RemoteDataService({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  static final RemoteDataService instance = RemoteDataService();

  final ApiClient _api;
  UserAccount? _currentUser;

  Never _unavailable(String method) {
    throw RemoteUnavailableException(
      '$method is not available from remote service yet.',
    );
  }

  List<Map<String, Object?>> _listOfMaps(Object? raw) {
    if (raw is! List) {
      throw RemoteDataException('Expected array response.');
    }
    return raw
        .map((item) {
          if (item is! Map) {
            throw RemoteDataException(
              'Expected every array item to be an object.',
            );
          }
          return Map<String, Object?>.from(item);
        })
        .toList(growable: false);
  }

  Map<String, Object?> _map(Object? raw) {
    if (raw is! Map) {
      throw RemoteDataException('Expected object response.');
    }
    return Map<String, Object?>.from(raw);
  }

  @override
  Future<EmotionType> getCurrentEmotion() async =>
      _unavailable('getCurrentEmotion');

  @override
  Future<EnergyStatus> getEnergyStatus() async =>
      _unavailable('getEnergyStatus');

  @override
  Future<EmotionState> getEmotionState() async =>
      _unavailable('getEmotionState');

  @override
  Future<void> addEmotionCheckIn(EmotionCheckIn checkIn) async =>
      Future.error(_unavailable('addEmotionCheckIn'));

  @override
  Future<List<EmotionCheckIn>> getEmotionCheckIns(DateTime day) async =>
      Future.error(_unavailable('getEmotionCheckIns'));

  @override
  Future<List<Goal>> getGoals() async => Future.error(_unavailable('getGoals'));

  @override
  Future<void> upsertGoal(Goal goal) async =>
      Future.error(_unavailable('upsertGoal'));

  @override
  Future<void> deleteGoal(String goalId) async =>
      Future.error(_unavailable('deleteGoal'));

  @override
  Future<Task> getCurrentTask() async =>
      Future.error(_unavailable('getCurrentTask'));

  @override
  Future<List<Task>> getNextTasks() async =>
      Future.error(_unavailable('getNextTasks'));

  @override
  Future<List<ScheduleEntry>> getScheduleEntries() async {
    final raw = await _api.get('/schedule');
    return _listOfMaps(raw).map(ScheduleEntry.fromJson).toList();
  }

  @override
  Future<void> addScheduleEntry(ScheduleEntry entry) async {
    if (entry.id == null || entry.id!.isEmpty) {
      await _api.post('/schedule', entry.toJson());
    } else {
      await _api.put('/schedule/${entry.id}', entry.toJson());
    }
  }

  @override
  Future<void> removeScheduleEntry(ScheduleEntry entry) async {
    final id = entry.id;
    if (id == null || id.isEmpty) return;
    await _api.delete('/schedule/$id');
  }

  @override
  Future<List<MicroTask>> getMicroTasks() async {
    final raw = await _api.get('/microtasks');
    return _listOfMaps(raw).map(MicroTask.fromJson).toList();
  }

  @override
  Future<void> addMicroTask(MicroTask task) async {
    await _api.post('/microtasks', task.toJson());
  }

  @override
  Future<void> removeMicroTask(MicroTask task) async {
    final id = task.id;
    if (id == null || id.isEmpty) return;
    await _api.delete('/microtasks/$id');
  }

  @override
  Future<void> updateMicroTask(MicroTask task) async {
    final id = task.id;
    if (id == null || id.isEmpty) {
      await addMicroTask(task);
      return;
    }
    await _api.put('/microtasks/$id', task.toJson());
  }

  @override
  Future<List<TeamMember>> getTeamMembers() async =>
      Future.error(_unavailable('getTeamMembers'));

  @override
  Future<UserProfile> getUserProfile() async {
    final user = await getCurrentUser();
    if (user == null) {
      return const UserProfile(displayName: 'remote', status: 'offline');
    }
    return UserProfile(displayName: user.displayName, status: 'online');
  }

  @override
  Future<void> logTaskEvent(TaskEvent event) async {
    await _api.post('/events', event.toJson());
  }

  @override
  Future<void> upsertTaskEvents(List<TaskEvent> events) async {
    if (events.isEmpty) return;
    await _api.post(
      '/events/batch',
      events.map((event) => event.toJson()).toList(growable: false),
    );
  }

  @override
  Future<List<TaskEvent>> getTaskEvents(DateTime from, DateTime to) async {
    final fromQuery = Uri.encodeQueryComponent(from.toIso8601String());
    final toQuery = Uri.encodeQueryComponent(to.toIso8601String());
    final raw = await _api.get('/events?from=$fromQuery&to=$toQuery');
    return _listOfMaps(raw).map(TaskEvent.fromJson).toList();
  }

  @override
  Future<ReviewReport> getWeeklyReport(DateTime weekStart) async {
    final day = _dateOnly(weekStart);
    final raw = await _api.get('/review/weekly?week_start=$day');
    return ReviewReport.fromJson(_map(raw));
  }

  @override
  Future<SchedulingTuning> getSchedulingTuning() async {
    final raw = await _api.get('/review/tuning');
    return SchedulingTuning.fromJson(_map(raw));
  }

  @override
  Future<String?> getFavoriteDevice() async =>
      Future.error(_unavailable('getFavoriteDevice'));

  @override
  Future<void> setFavoriteDevice(String deviceId) async =>
      Future.error(_unavailable('setFavoriteDevice'));

  @override
  Future<List<TeamMemberCalendar>> getTeamCalendars(DateTime day) async =>
      Future.error(_unavailable('getTeamCalendars'));

  @override
  Future<void> updateTeamSharePermission(
    String memberId,
    TeamSharePermission permission,
  ) async => Future.error(_unavailable('updateTeamSharePermission'));

  @override
  Future<void> bookTeamMeeting(
    DateTime day,
    TeamMeetingRequest request,
  ) async => Future.error(_unavailable('bookTeamMeeting'));

  @override
  Future<void> setSchedulingTuning(SchedulingTuning tuning) async {
    await _api.put('/review/tuning', tuning.toJson());
  }

  @override
  Future<String> getThemeMode() async =>
      Future.error(_unavailable('getThemeMode'));

  @override
  Future<void> setThemeMode(String themeMode) async =>
      Future.error(_unavailable('setThemeMode'));

  @override
  Future<String> getLocale() async => Future.error(_unavailable('getLocale'));

  @override
  Future<void> setLocale(String locale) async =>
      Future.error(_unavailable('setLocale'));

  @override
  Future<UserAccount?> getCurrentUser() async {
    if (_currentUser != null) {
      return _currentUser;
    }

    try {
      final raw = await _api.get('/auth/me');
      _currentUser = UserAccount.fromJson(_map(raw));
      return _currentUser;
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        return null;
      }
      rethrow;
    }
  }

  @override
  Future<bool> login(String account, String password) async {
    final raw = await _api.post('/auth/login', {
      'contactAddress': account,
      'password': password,
    });
    final data = _map(raw);
    _api.setToken(data['accessToken'] as String?);
    _currentUser = UserAccount.fromJson(_map(data['user']));
    return true;
  }

  @override
  Future<bool> registerAccount({
    required String username,
    required String password,
  }) async {
    final raw = await _api.post('/auth/register', {
      'contactAddress': username,
      'displayName': username,
      'password': password,
    });
    final data = _map(raw);
    _api.setToken(data['accessToken'] as String?);
    _currentUser = UserAccount.fromJson(_map(data['user']));
    return true;
  }

  @override
  Future<void> logout() async {
    _api.setToken(null);
    _currentUser = null;
  }

  String _dateOnly(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}
