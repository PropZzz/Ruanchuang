import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shixuzhipei/models/models.dart';
import 'package:shixuzhipei/theme/app_theme.dart';
import 'package:shixuzhipei/widgets/focus_task_card.dart';

void main() {
  testWidgets('focus task card uses the Stitch timer composition on mobile', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: FocusTaskCard(
          task: ScheduleEntry(
            title: '生产网关鉴权补丁',
            tag: '核心攻坚',
            height: 80,
            color: AppThemeTokens.actionLight,
            time: const TimeOfDay(hour: 10, minute: 0),
          ),
          remainingSeconds: 1419,
          isRunning: true,
          onStart: () {},
          onPause: () {},
          onFinish: () {},
          onRefresh: () {},
        ),
      ),
    );

    expect(find.byKey(const ValueKey('focus-mobile-timer')), findsOneWidget);
    expect(find.byKey(const ValueKey('focus-mobile-progress')), findsOneWidget);
    expect(find.text('暂停专注'), findsOneWidget);
  });
}
