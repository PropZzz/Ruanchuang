/// Versioned rescue strategy weights mirrored from the JSON contract.
class RescueStrategyWeights {
  static const schemaVersion = '1';
  static const policyVersion = '1';
  static const recoveryBufferMinutes = 15;
  static const hardConstraintOrder = <String>[
    'normalize',
    'fixedSchedule',
    'workWindows',
    'dependencies',
    'deadline',
  ];
  static const explanationCodeOrder = <String>[
    'deadline_proximity',
    'priority',
    'energy_fit',
    'kept_baseline',
    'fixed_conflict',
  ];
  static const _expectedHardConstraintOrder = [
    'normalize',
    'fixedSchedule',
    'workWindows',
    'dependencies',
    'deadline',
  ];
  static const _expectedExplanationCodeOrder = [
    'deadline_proximity',
    'priority',
    'energy_fit',
    'kept_baseline',
    'fixed_conflict',
  ];

  static const policies = <String, Map<String, String>>{
    'protectDeadline': {
      'scenario': 'deadlineFirst',
      'fixedSchedule': 'preserve',
      'baselinePolicy': 'reflowNonFixed',
      'deadlinePolicy': 'prioritizeDueDates',
      'lowEnergyPolicy': 'preferMatchingLoad',
      'movementPolicy': 'reflowNonFixedBaseline',
      'recoveryPolicy': 'none',
      'overdueRiskPolicy': 'deadlineIssues',
    },
    'protectRecovery': {
      'scenario': 'recoveryFirst',
      'fixedSchedule': 'preserve',
      'baselinePolicy': 'reflowNonFixed',
      'deadlinePolicy': 'preserveHardDeadlines',
      'lowEnergyPolicy': 'lowerTargetEnergy',
      'movementPolicy': 'reflowNonFixedBaseline',
      'recoveryPolicy': 'insert15MinuteBuffer',
      'overdueRiskPolicy': 'deadlineIssues',
    },
    'minimizeChanges': {
      'scenario': 'baselineFirst',
      'fixedSchedule': 'preserveAndLockBaseline',
      'baselinePolicy': 'lockAll',
      'deadlinePolicy': 'hardDeadlineNoLateFallback',
      'lowEnergyPolicy': 'softPreferenceOnly',
      'movementPolicy': 'preserveBaseline',
      'recoveryPolicy': 'none',
      'overdueRiskPolicy': 'deadlineIssues',
    },
  };

  static const _policyValues = <String, Set<String>>{
    'scenario': {'deadlineFirst', 'recoveryFirst', 'baselineFirst'},
    'fixedSchedule': {'preserve', 'preserveAndLockBaseline'},
    'baselinePolicy': {'reflowNonFixed', 'lockAll'},
    'deadlinePolicy': {
      'prioritizeDueDates',
      'preserveHardDeadlines',
      'hardDeadlineNoLateFallback',
    },
    'lowEnergyPolicy': {
      'preferMatchingLoad',
      'lowerTargetEnergy',
      'softPreferenceOnly',
    },
    'movementPolicy': {'reflowNonFixedBaseline', 'preserveBaseline'},
    'recoveryPolicy': {'none', 'insert15MinuteBuffer'},
    'overdueRiskPolicy': {'deadlineIssues'},
  };

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
    const expected = {
      'urgency',
      'priority',
      'energyFit',
      'stability',
      'recovery',
    };
    if (strategies.length != 3) {
      throw StateError('unexpected rescue strategy count');
    }
    if (policies.length != strategies.length ||
        hardConstraintOrder.length != _expectedHardConstraintOrder.length ||
        explanationCodeOrder.length != _expectedExplanationCodeOrder.length ||
        !_sameOrder(hardConstraintOrder, _expectedHardConstraintOrder) ||
        !_sameOrder(explanationCodeOrder, _expectedExplanationCodeOrder)) {
      throw StateError('invalid rescue policy order');
    }
    const expectedPolicy = {
      'scenario',
      'fixedSchedule',
      'baselinePolicy',
      'deadlinePolicy',
      'lowEnergyPolicy',
      'movementPolicy',
      'recoveryPolicy',
      'overdueRiskPolicy',
    };
    for (final entry in strategies.entries) {
      if (entry.value.keys.toSet().difference(expected).isNotEmpty ||
          expected.difference(entry.value.keys.toSet()).isNotEmpty) {
        throw StateError('incomplete weights for ${entry.key}');
      }
      if (entry.value.values.any((value) => value < 0)) {
        throw StateError('negative rescue weight for ${entry.key}');
      }
      final total = entry.value.values.fold<double>(
        0,
        (sum, value) => sum + value,
      );
      if ((total - 1.0).abs() > 0.000001) {
        throw StateError('weights for ${entry.key} must sum to 1');
      }
      final policy = policies[entry.key];
      if (policy == null ||
          policy.keys.toSet().difference(expectedPolicy).isNotEmpty ||
          expectedPolicy.difference(policy.keys.toSet()).isNotEmpty) {
        throw StateError('incomplete policy for ${entry.key}');
      }
      for (final field in expectedPolicy) {
        if (!_policyValues[field]!.contains(policy[field])) {
          throw StateError('unknown policy value for ${entry.key}.$field');
        }
      }
    }
  }

  static bool _sameOrder(List<String> actual, List<String> expected) {
    for (var index = 0; index < expected.length; index++) {
      if (actual[index] != expected[index]) return false;
    }
    return true;
  }
}
