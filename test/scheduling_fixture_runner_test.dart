import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shixuzhipei/services/scheduling/scheduler_core.dart';

import 'support/scheduling_fixture_runner.dart';

void main() {
  test('runner discovers every fixture and emits one complete payload', () {
    final directory =
        Platform.environment['SCHEDULING_FIXTURES_DIR'] ??
        'contracts/scheduling/v1/fixtures';
    final result = runFixtureDirectory(
      Directory(directory),
      core: const SchedulerCore(),
    );

    stdout.writeln('SCHEDULING_PARITY_RESULT_BEGIN');
    stdout.writeln(jsonEncode(result));
    stdout.writeln('SCHEDULING_PARITY_RESULT_END');

    expect(result['fixtures'], isA<List<dynamic>>());
    final expectedCount = Directory(directory)
        .listSync()
        .whereType<File>()
        .where(_isCanonicalFixture)
        .length;
    expect((result['fixtures'] as List).length, expectedCount);
    expect(result['invalid'], 0);
    expect(result['mismatched'], 0);
  });
}

bool _isCanonicalFixture(File file) {
  if (!file.path.toLowerCase().endsWith('.json')) return false;
  try {
    final value = jsonDecode(file.readAsStringSync());
    return value is Map &&
        value['request'] is Map &&
        (value['request'] as Map)['schemaVersion'] == '1';
  } on Object {
    return false;
  }
}
