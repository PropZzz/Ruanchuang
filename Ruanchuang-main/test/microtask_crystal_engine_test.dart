import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sxzppp/models/models.dart';
import 'package:sxzppp/services/microtask_crystals/heuristic_microtask_crystal_engine.dart';

int _m(TimeOfDay t) => t.hour * 60 + t.minute;

void main() {
  test('computeTimeCrystals returns gaps inside windows', () {
    const windows = [
      TimeWindow(
        start: TimeOfDay(hour: 8, minute: 0),
        end: TimeOfDay(hour: 12, minute: 0),
      ),
    ];

    final schedule = [
      ScheduleEntry(
        id: 'a',
        title: 'Busy1',
        tag: 'Core',
        height: (60 / 60.0) * 80.0,
        color: Colors.blue,
        time: const TimeOfDay(hour: 9, minute: 0),
      ),
      ScheduleEntry(
        id: 'b',
        title: 'Busy2',
        tag: 'Core',
        height: (30 / 60.0) * 80.0,
        color: Colors.blue,
        time: const TimeOfDay(hour: 11, minute: 0),
      ),
    ];

    final crystals = computeTimeCrystals(
      schedule: schedule,
      windows: windows,
      now: const TimeOfDay(hour: 8, minute: 0),
    );

    // Expect: 8:00-9:00, 10:00-11:00, 11:30-12:00
    expect(crystals.length, 3);
    expect(_m(crystals[0].start), 8 * 60);
    expect(crystals[0].minutes, 60);
    expect(_m(crystals[1].start), 10 * 60);
    expect(crystals[1].minutes, 60);
    expect(_m(crystals[2].start), 11 * 60 + 30);
    expect(crystals[2].minutes, 30);
  });

  test('heuristic matcher picks tasks that fit without overlapping core tasks', () {
    final engine = HeuristicMicroTaskCrystalEngine();

    const windows = [
      TimeWindow(
        start: TimeOfDay(hour: 8, minute: 0),
        end: TimeOfDay(hour: 10, minute: 0),
      ),
    ];

    final schedule = [
      ScheduleEntry(
        id: 'core',
        title: 'Core',
        tag: 'Core',
        height: (60 / 60.0) * 80.0,
        color: Colors.teal,
        time: const TimeOfDay(hour: 8, minute: 30),
      ),
    ];

    final microTasks = [
      MicroTask(id: 't1', title: 'Short', tag: 'Micro Task', minutes: 10),
      MicroTask(id: 't2', title: 'Fit', tag: 'Micro Task', minutes: 20),
      MicroTask(id: 't3', title: 'TooLong', tag: 'Micro Task', minutes: 90),
    ];

    final recs = engine.recommend(
      schedule: schedule,
      microTasks: microTasks,
      windows: windows,
      energy: EnergyTier.low,
      now: const TimeOfDay(hour: 8, minute: 0),
      maxRecommendations: 2,
    );

    expect(recs.isNotEmpty, isTrue);
    for (final r in recs) {
      // Must fit.
      expect(r.task.minutes <= r.crystal.minutes, isTrue);
      // Must start in window.
      expect(_m(r.crystal.start) >= 8 * 60, isTrue);
      expect(_m(r.crystal.start) < 10 * 60, isTrue);
      // Must not start inside core busy block 8:30-9:30.
      final s = _m(r.crystal.start);
      expect(s < 8 * 60 + 30 || s >= 9 * 60 + 30, isTrue);
    }
  });
}

