import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shixuzhipei/models/models.dart';
import 'package:shixuzhipei/services/emotion/emotion_policy.dart';

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
    test(
      'low emotion reduces density via rest blocks and caps high-load tasks',
      () {
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
        expect(
          adapted.where((t) => t.load == CognitiveLoad.low).single.priority,
          3,
        );

        final fixed = EmotionPolicy.fixedRestBlocks(
          day: DateTime(2026, 3, 15),
          emotion: EmotionState.tired,
        );
        expect(fixed.length, 2);
        expect(fixed.first.tag, '关怀');
        expect(fixed.first.title, '休息');
        expect(fixed.first.time, const TimeOfDay(hour: 10, minute: 30));
      },
    );

    test(
      'efficient emotion increases density via shorter duration and higher energy',
      () {
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
      },
    );

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

  group('EmotionPolicy guidance snapshot', () {
    test('efficient snapshot encourages deeper work and fewer rest blocks', () {
      final snapshot = EmotionPolicy.adaptiveSnapshot(
        emotion: EmotionState.efficient,
        recentCheckInCount: 2,
        careHint: false,
      );

      expect(snapshot.policy.energyDelta, 1);
      expect(snapshot.policy.durationMultiplier, 0.9);
      expect(snapshot.policy.maxHighLoadTasks, 3);
      expect(snapshot.policy.restMinutes, 0);
      expect(snapshot.headline, contains('深度'));
      expect(snapshot.highlights, contains('时长倍率 x0.9'));
      expect(snapshot.highlights, contains('今日已打卡 2 次'));
    });

    test('tired snapshot keeps care hint and rest guidance visible', () {
      final snapshot = EmotionPolicy.adaptiveSnapshot(
        emotion: EmotionState.tired,
        recentCheckInCount: 1,
        careHint: true,
      );

      expect(snapshot.policy.energyDelta, -1);
      expect(snapshot.policy.restMinutes, 15);
      expect(snapshot.highlights, contains('15 分钟休息块'));
      expect(snapshot.highlights, contains('已启用关怀提示'));
    });
  });
}
