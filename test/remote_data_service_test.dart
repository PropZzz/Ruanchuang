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
    const token = 'token-1';

    final client = MockClient((request) async {
      final path = request.url.path;
      final method = request.method;
      final auth = request.headers['authorization'] ?? request.headers['Authorization'];

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

    await service.logout();
    expect(await service.getCurrentUser(), isNull);
  });
}
