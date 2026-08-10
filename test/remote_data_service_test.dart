import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:shixuzhipei/models/models.dart';
import 'package:shixuzhipei/services/api_client.dart';
import 'package:shixuzhipei/services/remote_data_service.dart';

void main() {
  test('RemoteDataService handles auth and schedule/microtask CRUD', () async {
    final schedules = <Map<String, Object?>>[];
    final microTasks = <Map<String, Object?>>[];
    final events = <Map<String, Object?>>[];
    var tuning = <String, Object?>{
      'defaultDurationMultiplier': 1.0,
      'tagDurationMultiplier': <String, Object?>{},
      'highLoadPenaltyWhenLowEnergy': 1.0,
    };
    const token = 'token-1';

    final client = MockClient((request) async {
      final path = request.url.path;
      final method = request.method;
      final auth =
          request.headers['authorization'] ?? request.headers['Authorization'];

      Map<String, Object?> decodeBody() {
        final raw = request.body.trim();
        if (raw.isEmpty) return {};
        return Map<String, Object?>.from(jsonDecode(raw) as Map);
      }

      if (path == '/auth/register' && method == 'POST') {
        final body = decodeBody();
        return http.Response(
          jsonEncode({
            'accessToken': token,
            'tokenType': 'Bearer',
            'user': {
              'id': 'user-1',
              'contactAddress': body['contactAddress'],
              'displayName': body['displayName'] ?? body['contactAddress'],
            },
          }),
          200,
        );
      }

      if (path == '/auth/login' && method == 'POST') {
        return http.Response(
          jsonEncode({
            'accessToken': token,
            'tokenType': 'Bearer',
            'user': {
              'id': 'user-1',
              'contactAddress': 'alice@example.com',
              'displayName': 'Alice',
            },
          }),
          200,
        );
      }

      if (path == '/auth/me' && method == 'GET') {
        if (auth != 'Bearer $token') {
          return http.Response('Unauthorized', 401);
        }
        return http.Response(
          jsonEncode({
            'id': 'user-1',
            'contactAddress': 'alice@example.com',
            'displayName': 'Alice',
          }),
          200,
        );
      }

      if (path == '/schedule' && method == 'GET') {
        expect(auth, 'Bearer $token');
        return http.Response(jsonEncode(schedules), 200);
      }

      if (path == '/schedule' && method == 'POST') {
        expect(auth, 'Bearer $token');
        final body = decodeBody();
        schedules
          ..clear()
          ..add(Map<String, Object?>.from(body));
        return http.Response(jsonEncode(schedules.first), 200);
      }

      if (path.startsWith('/schedule/') && method == 'PUT') {
        expect(auth, 'Bearer $token');
        final body = decodeBody();
        schedules
          ..clear()
          ..add(Map<String, Object?>.from(body));
        return http.Response(jsonEncode(schedules.first), 200);
      }

      if (path.startsWith('/schedule/') && method == 'DELETE') {
        expect(auth, 'Bearer $token');
        schedules.clear();
        return http.Response('', 204);
      }

      if (path == '/microtasks' && method == 'GET') {
        expect(auth, 'Bearer $token');
        return http.Response(jsonEncode(microTasks), 200);
      }

      if (path == '/microtasks' && method == 'POST') {
        expect(auth, 'Bearer $token');
        final body = decodeBody();
        microTasks
          ..clear()
          ..add(Map<String, Object?>.from(body));
        return http.Response(jsonEncode(microTasks.first), 200);
      }

      if (path.startsWith('/microtasks/') && method == 'PUT') {
        expect(auth, 'Bearer $token');
        final body = decodeBody();
        microTasks
          ..clear()
          ..add(Map<String, Object?>.from(body));
        return http.Response(jsonEncode(microTasks.first), 200);
      }

      if (path.startsWith('/microtasks/') && method == 'DELETE') {
        expect(auth, 'Bearer $token');
        microTasks.clear();
        return http.Response('', 204);
      }

      if (path == '/events' && method == 'POST') {
        expect(auth, 'Bearer $token');
        final body = decodeBody();
        events
          ..clear()
          ..add(Map<String, Object?>.from(body));
        return http.Response(jsonEncode(events.first), 200);
      }

      if (path == '/events' && method == 'GET') {
        expect(auth, 'Bearer $token');
        return http.Response(jsonEncode(events), 200);
      }

      if (path == '/review/weekly' && method == 'GET') {
        expect(auth, 'Bearer $token');
        expect(request.url.queryParameters['week_start'], '2026-08-03');
        return http.Response(
          jsonEncode({
            'weekStart': '2026-08-03T00:00:00',
            'weekEnd': '2026-08-10T00:00:00',
            'startedCount': 2,
            'completedCount': 1,
            'completionRate': 0.5,
            'plannedMinutesTotal': 60,
            'actualMinutesTotal': 45,
            'actualDurationBuckets': {'31-60': 1},
            'delayAttribution': {'underestimated': 1},
            'suggestions': ['Keep recovery buffer.'],
            'tuning': {
              'defaultDurationMultiplier': 1.0,
              'tagDurationMultiplier': {'Focus': 1.15},
              'highLoadPenaltyWhenLowEnergy': 1.2,
            },
          }),
          200,
        );
      }

      if (path == '/review/tuning' && method == 'GET') {
        expect(auth, 'Bearer $token');
        return http.Response(jsonEncode(tuning), 200);
      }

      if (path == '/review/tuning' && method == 'PUT') {
        expect(auth, 'Bearer $token');
        tuning = decodeBody();
        return http.Response(jsonEncode(tuning), 200);
      }

      return http.Response('not found', 404);
    });

    final api = ApiClient(httpClient: client, baseUrl: 'http://server.test');
    final service = RemoteDataService(apiClient: api);

    expect(
      await service.registerAccount(
        username: 'alice@example.com',
        password: 'secret123',
      ),
      isTrue,
    );

    final currentUser = await service.getCurrentUser();
    expect(currentUser?.contactAddress, 'alice@example.com');

    await service.addScheduleEntry(
      ScheduleEntry(
        id: 'sch-1',
        title: 'Deep Work',
        tag: 'Focus',
        height: 72.5,
        color: const Color(0xFF00FF00),
        time: const TimeOfDay(hour: 9, minute: 30),
        goalId: 'goal-1',
        goalTaskId: 'task-1',
        reminderMinutesBefore: 15,
        repeat: RepeatFrequency.daily,
        repeatUntil: DateTime(2026, 6, 20),
      ),
    );

    final schedulesAfterWrite = await service.getScheduleEntries();
    expect(schedulesAfterWrite, hasLength(1));
    expect(schedulesAfterWrite.first.title, 'Deep Work');

    await service.addMicroTask(
      MicroTask(
        id: 'mt-1',
        title: 'Write notes',
        tag: 'Study',
        minutes: 25,
        priority: 4,
        requirement: 'Finish the summary',
        done: false,
      ),
    );

    final microTasksAfterWrite = await service.getMicroTasks();
    expect(microTasksAfterWrite, hasLength(1));
    expect(microTasksAfterWrite.first.priority, 4);

    await service.logTaskEvent(
      TaskEvent(
        id: 'rescue-1',
        taskId: 'urgent-1',
        title: 'Urgent task',
        tag: 'Urgent',
        at: DateTime(2026, 6, 14, 9),
        type: TaskEventType.interrupt,
        reason: 'rescue_accept:protectDeadline',
      ),
    );
    final eventsAfterWrite = await service.getTaskEvents(
      DateTime(2026, 6, 14),
      DateTime(2026, 6, 15),
    );
    expect(eventsAfterWrite.single.reason, 'rescue_accept:protectDeadline');

    final weeklyReport = await service.getWeeklyReport(DateTime(2026, 8, 3));
    expect(weeklyReport.startedCount, 2);
    expect(weeklyReport.tuning.tagDurationMultiplier['Focus'], 1.15);

    final defaultTuning = await service.getSchedulingTuning();
    expect(defaultTuning.defaultDurationMultiplier, 1.0);

    await service.setSchedulingTuning(
      const SchedulingTuning(
        defaultDurationMultiplier: 1.1,
        tagDurationMultiplier: {'Writing': 1.25},
        highLoadPenaltyWhenLowEnergy: 1.4,
      ),
    );
    final savedTuning = await service.getSchedulingTuning();
    expect(savedTuning.tagDurationMultiplier['Writing'], 1.25);

    await service.logout();
    expect(await service.getCurrentUser(), isNull);
  });

  test('RemoteDataService handles emotion energy goals and team basics', () async {
    final emotionCheckIns = <Map<String, Object?>>[];
    final goals = <Map<String, Object?>>[];
    final teamMembers = <Map<String, Object?>>[];
    const token = 'token-2';

    final client = MockClient((request) async {
      final path = request.url.path;
      final method = request.method;
      final auth =
          request.headers['authorization'] ?? request.headers['Authorization'];

      Map<String, Object?> decodeBody() {
        final raw = request.body.trim();
        if (raw.isEmpty) return {};
        return Map<String, Object?>.from(jsonDecode(raw) as Map);
      }

      if (path == '/auth/login' && method == 'POST') {
        return http.Response(
          jsonEncode({
            'accessToken': token,
            'tokenType': 'Bearer',
            'user': {
              'id': 'user-2',
              'contactAddress': 'bob@example.com',
              'displayName': 'Bob',
            },
          }),
          200,
        );
      }

      if (auth != 'Bearer $token') {
        return http.Response('Unauthorized', 401);
      }

      if (path == '/emotion/current' && method == 'GET') {
        return http.Response(
          jsonEncode(
            emotionCheckIns.isEmpty
                ? {
                    'id': null,
                    'at': null,
                    'state': 'stable',
                    'note': null,
                  }
                : emotionCheckIns.last,
          ),
          200,
        );
      }

      if (path == '/emotion/checkins' && method == 'POST') {
        final body = decodeBody();
        emotionCheckIns
          ..clear()
          ..add(body);
        return http.Response(jsonEncode(body), 200);
      }

      if (path == '/emotion/checkins' && method == 'GET') {
        expect(request.url.queryParameters['day'], '2026-08-09');
        return http.Response(jsonEncode(emotionCheckIns), 200);
      }

      if (path == '/energy/current' && method == 'GET') {
        return http.Response(
          jsonEncode({
            'id': 'energy-1',
            'at': '2026-08-09T10:00:00',
            'level': 'high',
            'status': 'flow',
            'description': 'Manual sample',
            'batteryPercent': 88,
            'emotion': 'stable',
            'flowState': 'focused',
            'source': 'manual',
          }),
          200,
        );
      }

      if (path == '/goals' && method == 'GET') {
        return http.Response(jsonEncode(goals), 200);
      }

      if (path == '/goals' && method == 'POST') {
        final body = decodeBody();
        goals
          ..clear()
          ..add(body);
        return http.Response(jsonEncode(body), 200);
      }

      if (path.startsWith('/goals/') && method == 'PUT') {
        final body = decodeBody();
        goals
          ..clear()
          ..add(body);
        return http.Response(jsonEncode(body), 200);
      }

      if (path.startsWith('/goals/') && method == 'DELETE') {
        goals.clear();
        return http.Response('', 204);
      }

      if (path == '/team/members' && method == 'GET') {
        return http.Response(jsonEncode(teamMembers), 200);
      }

      if (path == '/team/members' && method == 'POST') {
        final body = decodeBody();
        teamMembers
          ..clear()
          ..add(body);
        return http.Response(jsonEncode(body), 200);
      }

      if (path.startsWith('/team/members/') &&
          !path.endsWith('/permission') &&
          method == 'PUT') {
        final body = decodeBody();
        teamMembers
          ..clear()
          ..add(body);
        return http.Response(jsonEncode(body), 200);
      }

      if (path.startsWith('/team/members/') &&
          path.endsWith('/permission') &&
          method == 'PUT') {
        final body = decodeBody();
        final updated = {
          ...teamMembers.single,
          'permission': body['permission'],
        };
        teamMembers
          ..clear()
          ..add(updated);
        return http.Response(jsonEncode(updated), 200);
      }

      if (path == '/team/calendars' && method == 'GET') {
        expect(request.url.queryParameters['day'], '2026-08-09');
        return http.Response(jsonEncode(teamMembers), 200);
      }

      return http.Response('not found', 404);
    });

    final api = ApiClient(httpClient: client, baseUrl: 'http://server.test');
    final service = RemoteDataService(apiClient: api);

    expect(await service.login('bob@example.com', 'secret123'), isTrue);

    await service.addEmotionCheckIn(
      EmotionCheckIn(
        id: 'emotion-1',
        at: DateTime(2026, 8, 9, 9),
        state: EmotionState.tired,
        note: 'Need recovery',
      ),
    );
    expect(
      (await service.getEmotionCheckIns(DateTime(2026, 8, 9))).single.state,
      EmotionState.tired,
    );
    expect(await service.getEmotionState(), EmotionState.tired);
    expect(await service.getCurrentEmotion(), EmotionType.fatigue);

    final energy = await service.getEnergyStatus();
    expect(energy.level, 'high');
    expect(energy.batteryPercent, 88);
    expect(energy.flowState, 'focused');

    final goal = Goal(
      id: 'goal-1',
      title: 'Ship API',
      due: DateTime(2026, 8, 30, 18),
      priority: 5,
      tasks: const [
        GoalTask(
          id: 'goal-task-1',
          title: 'Remote methods',
          durationMinutes: 30,
          load: CognitiveLoad.medium,
          tag: 'Backend',
          dependsOn: ['spec'],
        ),
      ],
    );
    await service.upsertGoal(goal);
    expect((await service.getGoals()).single.tasks.single.dependsOn, ['spec']);

    await service.deleteGoal('goal-1');
    expect(await service.getGoals(), isEmpty);

    await service.upsertTeamMember(
      TeamMemberCalendar(
        memberId: 'member-1',
        displayName: 'Li Ming',
        role: 'PM',
        energy: EnergyTier.high,
        permission: TeamSharePermission.details,
        busy: [
          ScheduleEntry(
            id: 'busy-1',
            day: DateTime(2026, 8, 9),
            title: 'Sync',
            tag: 'Meeting',
            height: 80,
            color: const Color(0xFF2196F3),
            time: const TimeOfDay(hour: 9, minute: 0),
          ),
        ],
      ),
    );
    final calendars = await service.getTeamCalendars(DateTime(2026, 8, 9));
    expect(calendars.single.memberId, 'member-1');
    expect(calendars.single.busy.single.title, 'Sync');

    final overview = await service.getTeamMembers();
    expect(overview.single.name, 'Li Ming');
    expect(overview.single.isHighEnergy, isTrue);

    await service.updateTeamSharePermission(
      'member-1',
      TeamSharePermission.freeBusy,
    );
    expect(
      (await service.getTeamCalendars(DateTime(2026, 8, 9))).single.permission,
      TeamSharePermission.freeBusy,
    );
  });
}
