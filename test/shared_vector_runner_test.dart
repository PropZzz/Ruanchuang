import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/shared_vector_runner.dart';

void main() {
  test('runs all shared scheduling vectors and emits a parity payload', () async {
    final directory = Directory(
      Platform.environment['SHARED_VECTOR_FIXTURES_DIR'] ??
          defaultSharedVectorFixturesDirectory,
    );
    final result = await runSharedVectorDirectory(directory);
    stdout.writeln(formatSharedVectorResult(result));

    expect(result['fixtures'], isA<List<dynamic>>());
    expect((result['fixtures'] as List).length, 12);
    expect(result['invalid'], 0);
  });
}
