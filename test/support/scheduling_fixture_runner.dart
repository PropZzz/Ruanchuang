import 'dart:convert';
import 'dart:io';

import 'package:shixuzhipei/models/models.dart';
import 'package:shixuzhipei/services/scheduling/scheduler_core.dart';
import 'package:shixuzhipei/services/scheduling/scheduling_contract.dart';

Map<String, dynamic> runFixtureDirectory(
  Directory directory, {
  required SchedulerCore core,
}) {
  final files =
      directory
          .listSync()
          .whereType<File>()
          .where((file) => file.path.toLowerCase().endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  final results = <Map<String, dynamic>>[];
  for (final file in files) {
    final name = file.uri.pathSegments.last;
    try {
      final fixture = jsonDecode(file.readAsStringSync());
      final request = SchedulingContract.requestFromJson(
        Map<String, Object?>.from(fixture['request'] as Map),
      );
      final actual = core.plan(request);
      final canonical = SchedulingContract.planToJson(
        SchedulingPlan(
          schemaVersion: '1',
          entries: actual.entries
              .map((entry) => entry.copyWith(day: entry.day ?? request.day))
              .toList(growable: false),
          issues: actual.issues,
        ),
      );
      final expected = Map<String, Object?>.from(fixture['response'] as Map);
      final differences = compareCanonicalResults(expected, canonical);
      results.add({
        'name': name,
        'status': differences.isEmpty ? 'matched' : 'mismatched',
        'differences': differences,
        'actual': canonical,
      });
    } catch (error) {
      results.add({'name': name, 'status': 'invalid', 'error': '$error'});
    }
  }
  final mismatched = results
      .where((result) => result['status'] == 'mismatched')
      .length;
  final invalid = results
      .where((result) => result['status'] == 'invalid')
      .length;
  return {
    'fixtures': results,
    'matched': results.length - mismatched - invalid,
    'mismatched': mismatched,
    'invalid': invalid,
  };
}

List<Map<String, dynamic>> compareCanonicalResults(
  Map<String, Object?> expected,
  Map<String, Object?> actual,
) {
  final differences = <Map<String, dynamic>>[];
  _compareValue(expected['entries'], actual['entries'], 'entries', differences);
  _compareValue(expected['issues'], actual['issues'], 'issues', differences);
  _compareValue(expected['risk'], actual['risk'], 'risk', differences);
  if (expected['schemaVersion'] != actual['schemaVersion']) {
    differences.add({
      'field': 'schemaVersion',
      'expected': expected['schemaVersion'],
      'actual': actual['schemaVersion'],
    });
  }
  return differences;
}

void _compareValue(
  Object? expected,
  Object? actual,
  String path,
  List<Map<String, dynamic>> differences,
) {
  if (expected is List && actual is List) {
    if (expected.length != actual.length) {
      differences.add({
        'field': '$path.length',
        'expected': expected.length,
        'actual': actual.length,
      });
    }
    final count = expected.length < actual.length
        ? expected.length
        : actual.length;
    for (var i = 0; i < count; i++) {
      _compareValue(expected[i], actual[i], '$path[$i]', differences);
    }
    return;
  }
  if (expected is Map && actual is Map) {
    final keys = <Object?>{...expected.keys, ...actual.keys};
    for (final key in keys) {
      if (key == 'message') continue;
      _compareValue(expected[key], actual[key], '$path.$key', differences);
    }
    return;
  }
  if (expected != actual) {
    differences.add({'field': path, 'expected': expected, 'actual': actual});
  }
}
