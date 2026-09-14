import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shixuzhipei/services/scheduling/rescue_strategy_weights.dart';

void main() {
  test('Dart rescue weights match the versioned JSON contract', () {
    final payload =
        jsonDecode(
              File(
                'contracts/scheduling/v1/rescue-strategies.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    expect(payload['schemaVersion'], '1');
    expect(
      payload['recoveryBufferMinutes'],
      RescueStrategyWeights.recoveryBufferMinutes,
    );

    final strategies = payload['strategies'] as Map<String, dynamic>;
    const metricNames = {
      'urgency',
      'priority',
      'energyFit',
      'stability',
      'recovery',
    };
    for (final entry in RescueStrategyWeights.strategies.entries) {
      final expected = (strategies[entry.key] as Map<String, dynamic>);
      expect(
        entry.value,
        Map.fromEntries(
          expected.entries
              .where((item) => metricNames.contains(item.key))
              .map(
                (item) => MapEntry(item.key, (item.value as num).toDouble()),
              ),
        ),
      );
    }
    expect(payload['policyVersion'], RescueStrategyWeights.policyVersion);
    expect(
      payload['hardConstraintOrder'],
      RescueStrategyWeights.hardConstraintOrder,
    );
    expect(
      payload['explanationCodeOrder'],
      RescueStrategyWeights.explanationCodeOrder,
    );
  });

  test('Dart rescue weights are normalized', () {
    RescueStrategyWeights.validate();
    for (final weights in RescueStrategyWeights.strategies.values) {
      expect(weights.values.reduce((a, b) => a + b), closeTo(1.0, 0.000001));
    }
  });

  test(
    'Dart rescue policy matrix has stable orders and complete strategies',
    () {
      RescueStrategyWeights.validate();
      expect(RescueStrategyWeights.policyVersion, '1');
      expect(RescueStrategyWeights.hardConstraintOrder, <String>[
        'normalize',
        'fixedSchedule',
        'workWindows',
        'dependencies',
        'deadline',
      ]);
      expect(RescueStrategyWeights.explanationCodeOrder, <String>[
        'deadline_proximity',
        'priority',
        'energy_fit',
        'kept_baseline',
        'fixed_conflict',
      ]);
      expect(RescueStrategyWeights.hardConstraintOrder.toSet(), {
        'normalize',
        'fixedSchedule',
        'workWindows',
        'dependencies',
        'deadline',
      });
      expect(RescueStrategyWeights.explanationCodeOrder.toSet(), {
        'deadline_proximity',
        'priority',
        'energy_fit',
        'kept_baseline',
        'fixed_conflict',
      });
      for (final policy in RescueStrategyWeights.policies.values) {
        expect(policy.keys.toSet(), {
          'scenario',
          'fixedSchedule',
          'baselinePolicy',
          'deadlinePolicy',
          'lowEnergyPolicy',
          'movementPolicy',
          'recoveryPolicy',
          'overdueRiskPolicy',
        });
      }
    },
  );
}
