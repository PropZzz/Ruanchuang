import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/shared_vector_runner.dart';

void main() {
  test(
    'runs all shared scheduling vectors and emits a parity payload',
    () async {
      final directory = Directory(
        Platform.environment['SHARED_VECTOR_FIXTURES_DIR'] ??
            defaultSharedVectorFixturesDirectory,
      );
      final result = await runSharedVectorDirectory(directory);
      stdout.writeln(formatSharedVectorResult(result));

      final fixtureCount = directory
          .listSync()
          .whereType<File>()
          .where((file) => file.path.toLowerCase().endsWith('.json'))
          .length;
      final fixtures = result['fixtures'] as List;
      expect(result['fixtures'], isA<List<dynamic>>());
      expect(fixtures.length, fixtureCount);
      expect(fixtureCount, greaterThan(0));
      expect(result['invalid'], 0);
    },
  );
}
