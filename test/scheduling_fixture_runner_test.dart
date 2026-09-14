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
    expect((result['fixtures'] as List).length, 2);
    expect(result['invalid'], 0);
    expect(result['mismatched'], 0);
  });
}
