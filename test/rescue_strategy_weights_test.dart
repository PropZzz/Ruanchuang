import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shixuzhipei/services/scheduling/rescue_strategy_weights.dart';

void main() {
  test('Dart rescue weights match the versioned JSON contract', () {
    final payload = jsonDecode(
      File('contracts/scheduling/v1/rescue-strategies.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(payload['schemaVersion'], '1');
    expect(payload['recoveryBufferMinutes'], RescueStrategyWeights.recoveryBufferMinutes);

    final strategies = payload['strategies'] as Map<String, dynamic>;
    for (final entry in RescueStrategyWeights.strategies.entries) {
      final expected = (strategies[entry.key] as Map<String, dynamic>);
      expect(entry.value, expected.map((key, value) => MapEntry(key, (value as num).toDouble())));
    }
  });

  test('Dart rescue weights are normalized', () {
    RescueStrategyWeights.validate();
    for (final weights in RescueStrategyWeights.strategies.values) {
      expect(weights.values.reduce((a, b) => a + b), closeTo(1.0, 0.000001));
    }
  });
}
