import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sxzppp/models/models.dart';
import 'package:sxzppp/services/emotion/emotion_policy.dart';

void main() {
  group('EmotionPolicy care hint', () {
    test('shows care hint when today and yesterday are low', () {
      expect(
        EmotionPolicy.shouldShowCareHint(
          today: EmotionState.tired,
          yesterday: EmotionState.irritable,
        ),
        isTrue,
      );
    });

    test('does not show care hint when any day is non-low', () {
      expect(
        EmotionPolicy.shouldShowCareHint(
          today: EmotionState.stable,
          yesterday: EmotionState.tired,
        ),
        isFalse,
      );
    });
  });

  group('EmotionPolicy scheduling adaptation', () {
    test('low emotion reduces density via rest blocks and caps high-load tasks', () {
      final tasks = [
        const PlanTask(
          id: 'h1',
          title: 'High 1',
          durationMinutes: 60,
          priority: 5,
          load: CognitiveLoad.high,
          tag: 'Deep',
        ),
        const PlanTask(
          id: 'h2',
          title: 'High 2',
          durationMinutes: 60,
          priority: 4,
          load: CognitiveLoad.high,
          tag: 'Deep',
        ),
        const PlanTask(
          id: 'l1',
          title: 'Low 1',
          durationMinutes: 15,
          priority: 2,
          load: CognitiveLoad.low,
          tag: 'Micro',
        ),
      ];

      final adapted = EmotionPolicy.adaptTasks(
        tasks: tasks,
        emotion: EmotionState.tired,
      );
      expect(adapted.where((t) => t.load == CognitiveLoad.high).length, 1);
      expect(adapted.where((t) => t.load == CognitiveLoad.low).single.priority, 3);

      final fixed = EmotionPolicy.fixedRestBlocks(
        day: DateTime(2026, 3, 15),
        emotion: EmotionState.tired,
      );
      expect(fixed.length, 2);
      expect(fixed.first.tag, 'Care');
      expect(fixed.first.title, 'Rest');
      expect(fixed.first.time, const TimeOfDay(hour: 10, minute: 30));
    });

    test('efficient emotion increases density via shorter duration and higher energy', () {
      expect(
        EmotionPolicy.applyDurationMultiplier(
          minutes: 100,
          emotion: EmotionState.efficient,
        ),
        lessThan(100),
      );

      expect(
        EmotionPolicy.adjustEnergy(
          base: EnergyTier.medium,
          emotion: EmotionState.efficient,
        ),
        EnergyTier.high,
      );

      final fixed = EmotionPolicy.fixedRestBlocks(
        day: DateTime(2026, 3, 15),
        emotion: EmotionState.efficient,
      );
      expect(fixed, isEmpty);
    });

    test('low emotion decreases energy', () {
      expect(
        EmotionPolicy.adjustEnergy(
          base: EnergyTier.medium,
          emotion: EmotionState.irritable,
        ),
        EnergyTier.low,
      );
    });
  });
}

