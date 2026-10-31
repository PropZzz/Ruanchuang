import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shixuzhipei/models/models.dart';
import 'package:shixuzhipei/theme/app_theme.dart';
import 'package:shixuzhipei/widgets/focus_task_card.dart';

void main() {
  Widget app(Widget child) {
    return MaterialApp(
      theme: AppTheme.light,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: child,
    );
  }

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

  testWidgets('focus task card shows real cognitive load and tag chips', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      app(
        FocusTaskCard(
          task: ScheduleEntry(
            title: '生产网关鉴权补丁',
            tag: 'Deep Work',
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

    // No stored load: the chip derives it from the entry's own tag/duration.
    expect(find.text('负荷 高'), findsOneWidget);
    expect(find.text('深度工作'), findsWidgets);
    expect(find.text('P0 核心攻坚'), findsNothing);
  });

  testWidgets('focus task card previews a not-yet-started task', (tester) async {
    tester.view.physicalSize = const Size(390, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      app(
        FocusTaskCard(
          task: ScheduleEntry(
            title: '周会同步',
            tag: 'Meeting',
            height: 40,
            color: AppThemeTokens.actionLight,
            time: const TimeOfDay(hour: 14, minute: 0),
          ),
          remainingSeconds: 1800,
          isRunning: false,
          isNextTask: true,
          onStart: () {},
          onPause: () {},
          onFinish: () {},
          onRefresh: () {},
        ),
      ),
    );

    // The countdown shows the planned block length and the settle action
    // stays hidden until the task actually runs.
    expect(find.text('30:00'), findsOneWidget);
    expect(find.text('开始专注'), findsOneWidget);
    expect(find.text('结算'), findsNothing);
  });
}
