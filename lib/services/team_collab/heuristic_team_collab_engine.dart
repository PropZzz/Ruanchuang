import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../microtask_crystals/heuristic_microtask_crystal_engine.dart';
import '../microtask_crystals/microtask_crystal_engine.dart';
import 'team_collab_engine.dart';

int _m(TimeOfDay t) => t.hour * 60 + t.minute;

TimeOfDay _tod(int m) => TimeOfDay(hour: (m ~/ 60) % 24, minute: m % 60);

int _durFromHeight(double height) =>
    ((height / 80.0) * 60.0).round().clamp(1, 24 * 60).toInt();

bool _energyOk(EnergyTier v, EnergyTier min) => v.index >= min.index;

class HeuristicTeamCollabEngine implements TeamCollabEngine {
  @override
  TeamCollabResult compute({
    required DateTime day,
    required List<TimeWindow> windows,
    required List<TeamMemberCalendar> calendars,
    required int minParticipants,
    required int meetingMinutes,
    required EnergyTier minEnergy,
  }) {
    final overlaps = _pairwiseBusyOverlaps(calendars);

    final step = 5;

    final workIntervals = windows
        .map((w) => (_m(w.start), _m(w.end)))
        .where((p) => p.$2 > p.$1)
        .toList();

    final eligible =
        calendars.where((c) => _energyOk(c.energy, minEnergy)).toList();

    if (eligible.isEmpty || workIntervals.isEmpty) {
      return TeamCollabResult(goldenWindows: const [], busyOverlaps: overlaps);
    }

    final freeMap = <String, List<TimeCrystal>>{};
    for (final c in eligible) {
      freeMap[c.memberId] = computeTimeCrystals(
        schedule: c.busy,
        windows: windows,
        now: const TimeOfDay(hour: 0, minute: 0),
      );
    }

    bool isFree(String memberId, int minute) {
      final crystals = freeMap[memberId];
      if (crystals == null) return false;
      for (final cr in crystals) {
        final s = _m(cr.start);
        final e = s + cr.minutes;
        if (minute >= s && minute < e) return true;
      }
      return false;
    }

    final segments = <GoldenWindow>[];

    for (final (ws, we) in workIntervals) {
      int? segStart;
      final segMembers = <String>[];

      void closeSeg(int endMin, List<String> members) {
        if (segStart == null) return;
        final len = endMin - segStart!;
        if (len >= meetingMinutes) {
          final score = members.length * 10.0 - segStart! / 1000.0;
          segments.add(
            GoldenWindow(
              start: _tod(segStart!),
              minutes: len,
              participantIds: List<String>.from(members),
              score: score,
            ),
          );
        }
        segStart = null;
        members.clear();
      }

      for (var t = ws; t + meetingMinutes <= we; t += step) {
        final freeMembers = <String>[];
        for (final c in eligible) {
          if (isFree(c.memberId, t)) freeMembers.add(c.memberId);
        }

        bool durationOk() {
          for (var tt = t; tt < t + meetingMinutes; tt += step) {
            var cnt = 0;
            for (final id in freeMembers) {
              if (isFree(id, tt)) cnt++;
            }
            if (cnt < minParticipants) return false;
          }
          return true;
        }

        if (freeMembers.length >= minParticipants && durationOk()) {
          if (segStart == null) {
            segStart = t;
            segMembers
              ..clear()
              ..addAll(freeMembers);
          } else {
            segMembers.removeWhere((id) => !freeMembers.contains(id));
          }
        } else {
          closeSeg(t, segMembers);
        }
      }

      closeSeg(we, segMembers);
    }

    segments.sort((a, b) => b.score.compareTo(a.score));
    final dedup = <int, GoldenWindow>{};
    for (final w in segments) {
      final key = _m(w.start);
      dedup.putIfAbsent(key, () => w);
    }

    final out = dedup.values.toList()
      ..sort((a, b) => _m(a.start).compareTo(_m(b.start)));

    return TeamCollabResult(
      goldenWindows: out.take(5).toList(),
      busyOverlaps: overlaps,
    );
  }

  @override
  List<String> conflictsFor({
    required DateTime day,
    required TimeOfDay start,
    required int minutes,
    required List<TeamMemberCalendar> calendars,
  }) {
    final s = _m(start);
    final e = s + minutes;
    final conflicts = <String>[];

    for (final c in calendars) {
      for (final b in c.busy) {
        final bs = _m(b.time);
        final be = bs + _durFromHeight(b.height);
        final overlap = !(e <= bs || s >= be);
        if (overlap) {
          conflicts.add(c.displayName);
          break;
        }
      }
    }

    return conflicts;
  }

  List<TeamConflict> _pairwiseBusyOverlaps(List<TeamMemberCalendar> calendars) {
    final out = <TeamConflict>[];

    for (var i = 0; i < calendars.length; i++) {
      for (var j = i + 1; j < calendars.length; j++) {
        final a = calendars[i];
        final b = calendars[j];

        for (final ba in a.busy) {
          final as = _m(ba.time);
          final ae = as + _durFromHeight(ba.height);
          for (final bb in b.busy) {
            final bs = _m(bb.time);
            final be = bs + _durFromHeight(bb.height);
            final s = as > bs ? as : bs;
            final e = ae < be ? ae : be;
            if (e > s) {
              out.add(
                TeamConflict(
                  memberA: a.displayName,
                  memberB: b.displayName,
                  start: _tod(s),
                  end: _tod(e),
                ),
              );
            }
          }
        }
      }
    }

    out.sort((x, y) => _m(x.start).compareTo(_m(y.start)));
    return out.take(8).toList();
  }
}
