import 'package:flutter/material.dart';

import '../../models/models.dart';

abstract class TeamCollabEngine {
  TeamCollabResult compute({
    required DateTime day,
    required List<TimeWindow> windows,
    required List<TeamMemberCalendar> calendars,
    required int minParticipants,
    required int meetingMinutes,
    required EnergyTier minEnergy,
  });

  /// For ad-hoc user-selected time checks.
  List<String> conflictsFor({
    required DateTime day,
    required TimeOfDay start,
    required int minutes,
    required List<TeamMemberCalendar> calendars,
  });
}

class TeamCollabResult {
  final List<GoldenWindow> goldenWindows;
  final List<TeamConflict> busyOverlaps;

  const TeamCollabResult({
    required this.goldenWindows,
    required this.busyOverlaps,
  });
}
