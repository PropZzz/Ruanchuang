import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shixuzhipei/theme/app_theme.dart';

void main() {
  test('accent preset is applied to the semantic tertiary color', () {
    final theme = AppTheme.build(
      Brightness.light,
      accentColor: const Color(0xFF6E8E7D),
    );

    expect(theme.colorScheme.tertiary, const Color(0xFF6E8E7D));
  });
}
