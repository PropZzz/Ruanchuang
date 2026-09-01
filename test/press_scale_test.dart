import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shixuzhipei/widgets/press_scale.dart';

void main() {
  testWidgets('press scale gives tactile feedback and restores on release', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PressScale(
          child: Center(
            child: const SizedBox(
              key: ValueKey('press-target'),
              width: 100,
              height: 44,
            ),
          ),
        ),
      ),
    );

    final target = find.byKey(const ValueKey('press-target'));
    final gesture = await tester.startGesture(tester.getCenter(target));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      tester
          .widget<AnimatedScale>(
            find.byKey(const ValueKey('press-scale-animation')),
          )
          .scale,
      closeTo(0.96, 0.001),
    );
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 120));
    expect(
      tester
          .widget<AnimatedScale>(
            find.byKey(const ValueKey('press-scale-animation')),
          )
          .scale,
      closeTo(1, 0.001),
    );
  });
}
