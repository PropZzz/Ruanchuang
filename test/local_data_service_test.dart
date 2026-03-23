import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shixuzhipei/models/models.dart';
import 'package:shixuzhipei/services/local_data_service.dart';
import 'package:shixuzhipei/services/local_persistence/local_persistence.dart';

void main() {
  test('LocalDataService migrates legacy keys and persists ids', () async {
    final persistence = InMemoryLocalPersistence();
    final legacyEntry = <String, Object?>{
      'title': 'Legacy Task',
      'tag': 'Legacy',
      'height': 80.0,
      'color': Colors.teal.toARGB32(),
      'time': const {'hour': 9, 'minute': 0},
    };
    final legacyPayload = <String, Object?>{
      'version': 1,
      'scheduleEntries': [legacyEntry],
    };
    await persistence.write(jsonEncode(legacyPayload));

    final service = LocalDataService.forPersistence(persistence);
    final entries = await service.getScheduleEntries();

    expect(entries.length, 1);
    expect(entries.first.id, isNotNull);
    expect(entries.first.id!.isNotEmpty, true);

    final savedRaw = await persistence.read();
    expect(savedRaw, isNotNull);
    final saved = Map<String, Object?>.from(
      jsonDecode(savedRaw!) as Map<dynamic, dynamic>,
    );
    expect(saved['schedule'], isA<List>());
    expect(saved['scheduleEntries'], isNull);
    expect(saved['version'], isA<int>());

    final schedule = (saved['schedule'] as List).cast<Map<dynamic, dynamic>>();
    final savedId = schedule.first['id'] as String?;
    expect(savedId, isNotNull);
    expect(savedId!.isNotEmpty, true);
  });

  test('LocalDataService upserts schedule entries by id', () async {
    final persistence = InMemoryLocalPersistence();
    final service = LocalDataService.forPersistence(persistence);

    final entry = ScheduleEntry(
      id: 'sch_test_unique',
      title: 'Original',
      tag: 'Focus',
      height: 80.0,
      color: Colors.teal,
      time: const TimeOfDay(hour: 9, minute: 0),
    );
    await service.addScheduleEntry(entry);
    await service.addScheduleEntry(entry.copyWith(title: 'Updated'));

    final entries = await service.getScheduleEntries();
    final testEntry = entries.firstWhere((e) => e.id == 'sch_test_unique');
    expect(testEntry.title, 'Updated');

    final savedRaw = await persistence.read();
    final saved = Map<String, Object?>.from(
      jsonDecode(savedRaw!) as Map<dynamic, dynamic>,
    );
    final schedule = (saved['schedule'] as List).cast<Map<dynamic, dynamic>>();
    final savedEntry = schedule.firstWhere((e) => e['id'] == 'sch_test_unique');
    expect(savedEntry['title'], 'Updated');
  });

  test('LocalDataService persists team permission updates', () async {
    final persistence = InMemoryLocalPersistence();
    final service = LocalDataService.forPersistence(persistence);
    final day = DateTime(2026, 1, 1);

    final calendars = await service.getTeamCalendars(day);
    expect(calendars.isNotEmpty, isTrue);
    final member = calendars.first;
    final nextPermission = member.permission == TeamSharePermission.details
        ? TeamSharePermission.freeBusy
        : TeamSharePermission.details;

    await service.updateTeamSharePermission(member.memberId, nextPermission);

    final reloaded = LocalDataService.forPersistence(persistence);
    final calendars2 = await reloaded.getTeamCalendars(day);
    final updated = calendars2.firstWhere((c) => c.memberId == member.memberId);

    expect(updated.permission, nextPermission);
  });

  test('LocalDataService derives team members with progress', () async {
    final persistence = InMemoryLocalPersistence();
    final service = LocalDataService.forPersistence(persistence);

    final members = await service.getTeamMembers();

    expect(members, isNotEmpty);
    expect(members.first.progress, inInclusiveRange(0.0, 1.0));
  });
}
