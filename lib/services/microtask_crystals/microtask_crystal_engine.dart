import 'package:flutter/material.dart';

import '../../models/models.dart';

class TimeCrystal {
  final TimeOfDay start;
  final int minutes;

  const TimeCrystal({required this.start, required this.minutes});

  String get bucket {
    if (minutes <= 10) return '<=10';
    if (minutes <= 30) return '10-30';
    if (minutes <= 60) return '30-60';
    return '60+';
  }
}

class TimeCrystalRecommendation {
  final TimeCrystal crystal;
  final MicroTask task;
  final double score;

  const TimeCrystalRecommendation({
    required this.crystal,
    required this.task,
    required this.score,
  });
}

abstract class MicroTaskCrystalEngine {
  List<TimeCrystalRecommendation> recommend({
    required List<ScheduleEntry> schedule,
    required List<MicroTask> microTasks,
    required List<TimeWindow> windows,
    required EnergyTier energy,
    required TimeOfDay now,
    int maxRecommendations = 5,
  });
}
