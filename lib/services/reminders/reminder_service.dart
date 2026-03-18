import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/models.dart';
import 'reminder_notifier.dart';

class PlannedReminder {
  final String key;
  final DateTime startAt;
  final DateTime intendedFireAt;
  final DateTime scheduledAt;
  final int minutesBefore;

  const PlannedReminder({
    required this.key,
    required this.startAt,
    required this.intendedFireAt,
    required this.scheduledAt,
    required this.minutesBefore,
  });
}

class ReminderPlanRequest {
  final DateTime day;
  final DateTime now;
  final ScheduleEntry entry;
  final String entryKey;
  final int maxUpcomingOccurrences;

  const ReminderPlanRequest({
    required this.day,
    required this.now,
    required this.entry,
    required this.entryKey,
    required this.maxUpcomingOccurrences,
  });
}

typedef ReminderPlanner = List<PlannedReminder> Function(ReminderPlanRequest req);

class ReminderService {
  ReminderService({Map<String, ReminderPlanner>? plannersByTag})
      : _plannerRouter = _ReminderPlannerRouter(plannersByTag: plannersByTag);

  final ReminderNotifier _notifier = createReminderNotifier();
  final Map<String, Timer> _timers = {};
  final _ReminderPlannerRouter _plannerRouter;

  void dispose() {
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
  }

  Future<void> rescheduleDay({
    required DateTime day,
    required List<ScheduleEntry> entries,
  }) async {
    // P0 policy: clear and re-schedule for the current day's visible entries.
    dispose();
    final now = DateTime.now();
    for (final e in entries) {
      await scheduleEntry(day: day, entry: e, now: now);
    }
  }

  Future<void> scheduleEntry({
    required DateTime day,
    required ScheduleEntry entry,
    DateTime? now,
  }) async {
    final entryKey = (entry.id == null || entry.id!.isEmpty)
        ? _fallbackId(entry)
        : entry.id!;

    // Cancel any previous timers for the same entry.
    final prefix = '$entryKey|';
    final toCancel = _timers.keys.where((k) => k.startsWith(prefix)).toList();
    for (final k in toCancel) {
      _timers.remove(k)?.cancel();
    }

    final n = now ?? DateTime.now();
    final maxUpcoming = entry.repeat == RepeatFrequency.none ? 1 : 2;
    final planner = _plannerRouter.forEntry(entry);
    final planned = planner(
      ReminderPlanRequest(
        day: day,
        now: n,
        entry: entry,
        entryKey: entryKey,
        maxUpcomingOccurrences: maxUpcoming,
      ),
    );

    for (final p in planned) {
      _schedulePlanned(entry: entry, entryKey: entryKey, planned: p);
    }
  }

  @visibleForTesting
  static List<PlannedReminder> planReminders(ReminderPlanRequest req) {
    final minutesBefore = req.entry.reminderMinutesBefore;
    if (minutesBefore <= 0) return const [];

    final days = _upcomingOccurrenceDays(
      day: req.day,
      now: req.now,
      entry: req.entry,
      maxCount: req.maxUpcomingOccurrences,
    );

    final out = <PlannedReminder>[];
    for (final d in days) {
      final startAt = DateTime(
        d.year,
        d.month,
        d.day,
        req.entry.time.hour,
        req.entry.time.minute,
      );
      final intendedFireAt =
          startAt.subtract(Duration(minutes: minutesBefore));
      final scheduledAt = intendedFireAt.isAfter(req.now)
          ? intendedFireAt
          : req.now.add(const Duration(seconds: 1));
      out.add(
        PlannedReminder(
          key: _timerKey(
            entryKey: req.entryKey,
            startAt: startAt,
            phase: _phaseBeforeStart,
          ),
          startAt: startAt,
          intendedFireAt: intendedFireAt,
          scheduledAt: scheduledAt,
          minutesBefore: minutesBefore,
        ),
      );
    }

    return out;
  }

  static const String _phaseBeforeStart = 'before_start';

  static String _timerKey({
    required String entryKey,
    required DateTime startAt,
    required String phase,
  }) {
    return '$entryKey|${startAt.millisecondsSinceEpoch}|$phase';
  }

  static DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  static List<DateTime> _upcomingOccurrenceDays({
    required DateTime day,
    required DateTime now,
    required ScheduleEntry entry,
    required int maxCount,
  }) {
    final anchor = _dateOnly(day);
    final until =
        entry.repeatUntil == null ? null : _dateOnly(entry.repeatUntil!);

    final out = <DateTime>[];
    var d = anchor;
    var safety = 0;

    while (out.length < maxCount && safety < 3660) {
      if (until != null && d.isAfter(until)) break;

      final startAt = DateTime(
        d.year,
        d.month,
        d.day,
        entry.time.hour,
        entry.time.minute,
      );

      if (startAt.isAfter(now)) {
        out.add(d);
      }

      if (entry.repeat == RepeatFrequency.none) break;
      d = _addRepeat(d, entry.repeat);
      safety++;
    }

    return out;
  }

  static DateTime _addRepeat(DateTime day, RepeatFrequency repeat) {
    switch (repeat) {
      case RepeatFrequency.none:
        return day;
      case RepeatFrequency.daily:
        return day.add(const Duration(days: 1));
      case RepeatFrequency.weekly:
        return day.add(const Duration(days: 7));
      case RepeatFrequency.monthly:
        return _addMonthsClamped(day, 1);
    }
  }

  static int _daysInMonth(int year, int month) {
    final last = DateTime(year, month + 1, 0);
    return last.day;
  }

  static DateTime _addMonthsClamped(DateTime day, int months) {
    final monthIndex = day.month - 1 + months;
    final year = day.year + monthIndex ~/ 12;
    final month = (monthIndex % 12) + 1;
    final clampedDay = day.day.clamp(1, _daysInMonth(year, month));
    return DateTime(year, month, clampedDay);
  }

  void _schedulePlanned({
    required ScheduleEntry entry,
    required String entryKey,
    required PlannedReminder planned,
  }) {
    // Cancel any previous timer for the same planned key.
    _timers.remove(planned.key)?.cancel();

    final now = DateTime.now();
    final delay = planned.scheduledAt.difference(now);
    final safeDelay = delay.isNegative ? const Duration(seconds: 1) : delay;

    _timers[planned.key] = Timer(safeDelay, () async {
      _timers.remove(planned.key);

      await _fireReminder(
        entry: entry,
        entryKey: entryKey,
        startAt: planned.startAt,
        minutesBefore: planned.minutesBefore,
        isSnooze: false,
      );

      _scheduleNextOccurrenceIfNeeded(
        entry: entry,
        entryKey: entryKey,
        occurrenceStartAt: planned.startAt,
      );
    });
  }

  Future<void> _fireReminder({
    required ScheduleEntry entry,
    required String entryKey,
    required DateTime startAt,
    required int minutesBefore,
    required bool isSnooze,
  }) async {
    final title = 'Schedule reminder';
    final when = _fmtDateTime(startAt);

    final body = isSnooze
        ? '${entry.title} ($when)'
        : '${entry.title} starts at $when (in $minutesBefore min)';

    await _notifier.showReminder(
      title: title,
      body: body,
      actions: [
        ReminderAction(
          label: '5m',
          onPressed: () => _snooze(
            entry: entry,
            entryKey: entryKey,
            startAt: startAt,
            after: const Duration(minutes: 5),
          ),
        ),
        ReminderAction(
          label: '10m',
          onPressed: () => _snooze(
            entry: entry,
            entryKey: entryKey,
            startAt: startAt,
            after: const Duration(minutes: 10),
          ),
        ),
      ],
    );
  }

  void _snooze({
    required ScheduleEntry entry,
    required String entryKey,
    required DateTime startAt,
    required Duration after,
  }) {
    final key = _timerKey(entryKey: entryKey, startAt: startAt, phase: 'snooze');

    _timers.remove(key)?.cancel();
    _timers[key] = Timer(after, () async {
      _timers.remove(key);
      await _fireReminder(
        entry: entry,
        entryKey: entryKey,
        startAt: startAt,
        minutesBefore: entry.reminderMinutesBefore,
        isSnooze: true,
      );
    });
  }

  void _scheduleNextOccurrenceIfNeeded({
    required ScheduleEntry entry,
    required String entryKey,
    required DateTime occurrenceStartAt,
  }) {
    if (entry.repeat == RepeatFrequency.none) return;
    if (entry.reminderMinutesBefore <= 0) return;

    final occurrenceDay = _dateOnly(occurrenceStartAt);
    final nextDay = _addRepeat(occurrenceDay, entry.repeat);

    final until =
        entry.repeatUntil == null ? null : _dateOnly(entry.repeatUntil!);
    if (until != null && nextDay.isAfter(until)) return;

    final now = DateTime.now();
    final planner = _plannerRouter.forEntry(entry);
    final planned = planner(
      ReminderPlanRequest(
        day: nextDay,
        now: now,
        entry: entry,
        entryKey: entryKey,
        maxUpcomingOccurrences: 1,
      ),
    );

    for (final p in planned) {
      if (_timers.containsKey(p.key)) continue;
      _schedulePlanned(entry: entry, entryKey: entryKey, planned: p);
    }
  }

  String _fallbackId(ScheduleEntry e) {
    return '${e.title}|${e.tag}|${e.time.hour}:${e.time.minute}|${e.height}';
  }

  String _fmtDateTime(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$mm';
  }
}

class _ReminderPlannerRouter {
  _ReminderPlannerRouter({Map<String, ReminderPlanner>? plannersByTag})
      : _plannersByTag = plannersByTag ?? const {};

  final Map<String, ReminderPlanner> _plannersByTag;

  ReminderPlanner forEntry(ScheduleEntry entry) {
    // Extension point: route to different reminder strategies by tag.
    return _plannersByTag[entry.tag] ?? ReminderService.planReminders;
  }
}

