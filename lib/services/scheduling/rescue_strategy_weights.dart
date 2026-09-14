/// Versioned rescue strategy weights mirrored from the JSON contract.
class RescueStrategyWeights {
  static const schemaVersion = '1';
  static const recoveryBufferMinutes = 15;

  static const strategies = <String, Map<String, double>>{
    'protectDeadline': {
      'urgency': 0.55,
      'priority': 0.25,
      'energyFit': 0.10,
      'stability': 0.10,
      'recovery': 0.00,
    },
    'protectRecovery': {
      'urgency': 0.20,
      'priority': 0.10,
      'energyFit': 0.35,
      'stability': 0.10,
      'recovery': 0.25,
    },
    'minimizeChanges': {
      'urgency': 0.25,
      'priority': 0.15,
      'energyFit': 0.05,
      'stability': 0.55,
      'recovery': 0.00,
    },
  };

  static void validate() {
    const expected = {'urgency', 'priority', 'energyFit', 'stability', 'recovery'};
    if (strategies.length != 3) {
      throw StateError('unexpected rescue strategy count');
    }
    for (final entry in strategies.entries) {
      if (entry.value.keys.toSet().difference(expected).isNotEmpty ||
          expected.difference(entry.value.keys.toSet()).isNotEmpty) {
        throw StateError('incomplete weights for ${entry.key}');
      }
      if (entry.value.values.any((value) => value < 0)) {
        throw StateError('negative rescue weight for ${entry.key}');
      }
      final total = entry.value.values.fold<double>(0, (sum, value) => sum + value);
      if ((total - 1.0).abs() > 0.000001) {
        throw StateError('weights for ${entry.key} must sum to 1');
      }
    }
  }
}
