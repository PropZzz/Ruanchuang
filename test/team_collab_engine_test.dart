import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shixuzhipei/models/models.dart';
import 'package:shixuzhipei/services/team_collab/heuristic_team_collab_engine.dart';

void main() {
  test('golden window exists when two members share free time and energy', () {
    final engine = HeuristicTeamCollabEngine();

    const windows = [
      TimeWindow(start: TimeOfDay(hour: 9, minute: 0), end: TimeOfDay(hour: 12, minute: 0)),
    ];

    final a = TeamMemberCalendar(
      memberId: 'a',
      displayName: 'A',
      role: 'Dev',
      energy: EnergyTier.high,
      permission: TeamSharePermission.freeBusy,
      busy: const [
        ScheduleEntry(
          id: 'a1',
          title: 'busy',
          tag: 'Meeting',
          height: 80.0,
          color: Colors.blue,
          time: TimeOfDay(hour: 10, minute: 0),
        ),
      ],
    );

    final b = TeamMemberCalendar(
      memberId: 'b',
      displayName: 'B',
      role: 'PM',
      energy: EnergyTier.medium,
      permission: TeamSharePermission.freeBusy,
      busy: const [],
    );

    final res = engine.compute(
      day: DateTime(2026, 1, 1),
      windows: windows,
      calendars: [a, b],
      minParticipants: 2,
      meetingMinutes: 30,
      minEnergy: EnergyTier.medium,
    );

    // A is free 9:00-10:00 and 11:00-12:00, B is free all window. So should exist.
    expect(res.goldenWindows.isNotEmpty, isTrue);

    for (final w in res.goldenWindows) {
      expect(w.participantIds.length >= 2, isTrue);
    }
  });

  test('conflict check reports busy members for a proposed time', () {
    final engine = HeuristicTeamCollabEngine();

    final a = TeamMemberCalendar(
      memberId: 'a',
      displayName: 'A',
      role: 'Dev',
      energy: EnergyTier.high,
      permission: TeamSharePermission.freeBusy,
      busy: const [
        ScheduleEntry(
          id: 'a1',
          title: 'busy',
          tag: 'Meeting',
          height: 80.0,
          color: Colors.blue,
          time: TimeOfDay(hour: 10, minute: 0),
        ),
      ],
    );

    final conflicts = engine.conflictsFor(
      day: DateTime(2026, 1, 1),
      start: const TimeOfDay(hour: 10, minute: 0),
      minutes: 30,
      calendars: [a],
    );

    expect(conflicts, contains('A'));
  });
}
