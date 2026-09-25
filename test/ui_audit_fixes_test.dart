import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shixuzhipei/models/models.dart';
import 'package:shixuzhipei/screens/micro_task_page.dart';
import 'package:shixuzhipei/screens/smart_calendar_page.dart';
import 'package:shixuzhipei/screens/team_page.dart';
import 'package:shixuzhipei/services/app_services.dart';
import 'package:shixuzhipei/services/mock_data_service.dart';
import 'package:shixuzhipei/theme/app_theme.dart';
import 'package:shixuzhipei/utils/app_strings.dart';
import 'package:shixuzhipei/widgets/schedule_timeline.dart';

import 'support/noop_reminder_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppServices.installTestOverrides(
      dataService: MockDataService(),
      reminderService: NoopReminderService(),
    );
  });

  tearDown(AppServices.resetForTests);

  Widget app(Widget home, {Locale locale = const Locale('zh', 'CN')}) =>
      MaterialApp(
        locale: locale,
        supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: AppTheme.light,
        home: home,
      );

  testWidgets('refresh actions expose localized tooltips', (tester) async {
    await tester.pumpWidget(app(const MicroTaskPage()));
    await tester.pumpAndSettle();
    expect(find.byTooltip('刷新'), findsOneWidget);

    await tester.pumpWidget(app(const TeamPage()));
    await tester.pumpAndSettle();
    expect(find.byTooltip('刷新'), findsOneWidget);
  });

  testWidgets('English action tooltips are localized', (tester) async {
    const locale = Locale('en');

    await tester.pumpWidget(app(const MicroTaskPage(), locale: locale));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Refresh'), findsOneWidget);

    await tester.pumpWidget(app(const TeamPage(), locale: locale));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Refresh'), findsOneWidget);

    final service = MockDataService();
    final entry = ScheduleEntry(
      id: 'audit-calendar-delete-en',
      day: DateTime.now(),
      title: 'Calendar delete task',
      tag: 'Focus',
      height: 80,
      color: Colors.teal,
      time: const TimeOfDay(hour: 9, minute: 0),
    );
    await tester.runAsync(() => service.addScheduleEntry(entry));
    AppServices.installTestOverrides(
      dataService: service,
      reminderService: NoopReminderService(),
    );

    await tester.pumpWidget(app(const SmartCalendarPage(), locale: locale));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byTooltip('Previous period'), findsOneWidget);
    expect(find.byTooltip('Next period'), findsOneWidget);
    expect(find.byTooltip('Delete'), findsWidgets);
    await tester.runAsync(() => service.removeScheduleEntry(entry));
  });

  testWidgets('calendar period actions expose localized tooltips', (
    tester,
  ) async {
    await tester.pumpWidget(app(const SmartCalendarPage()));
    await tester.pumpAndSettle();

    expect(
      find.byTooltip(
        AppStrings.of(
          tester.element(find.byType(Scaffold).first),
          'calendar_previous_period',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byTooltip(
        AppStrings.of(
          tester.element(find.byType(Scaffold).first),
          'calendar_next_period',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('calendar timeline delete action exposes localized tooltip', (
    tester,
  ) async {
    final service = MockDataService();
    AppServices.installTestOverrides(
      dataService: service,
      reminderService: NoopReminderService(),
    );
    await tester.runAsync(
      () => service.addScheduleEntry(
        ScheduleEntry(
          id: 'audit-calendar-delete',
          day: DateTime.now(),
          title: 'Calendar delete task',
          tag: 'Focus',
          height: 80,
          color: Colors.teal,
          time: const TimeOfDay(hour: 9, minute: 0),
        ),
      ),
    );

    await tester.pumpWidget(app(const SmartCalendarPage()));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byTooltip('删除'), findsOneWidget);
  });

  testWidgets('timeline delete tooltip and calendar task text stay readable', (
    tester,
  ) async {
    final selectedDay = DateTime(2026, 9, 25);
    final entry = ScheduleEntry(
      id: 'audit-task',
      day: selectedDay,
      title: 'Readable task title',
      tag: 'Focused summary',
      height: 80,
      color: Colors.teal,
      time: const TimeOfDay(hour: 9, minute: 0),
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
        theme: AppTheme.light,
        home: Scaffold(
          body: ScheduleTimeline(
            view: ScheduleTimelineView.day,
            selectedDay: selectedDay,
            entries: [entry],
            deleteLabel: '删除',
            onDelete: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('删除'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
        theme: AppTheme.light,
        home: Scaffold(
          body: ScheduleTimeline(
            view: ScheduleTimelineView.month,
            selectedDay: selectedDay,
            entries: [entry],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      _effectiveFontSize(
        tester,
        find.textContaining('Readable task title').first,
      ),
      greaterThanOrEqualTo(12),
    );
    expect(
      _effectiveFontSize(tester, find.textContaining('Focused summary').first),
      greaterThanOrEqualTo(12),
    );
  });

  testWidgets('gantt duration metadata is at least 12 logical pixels', (
    tester,
  ) async {
    final selectedDay = DateTime(2026, 9, 25);
    final entry = ScheduleEntry(
      id: 'audit-gantt-task',
      day: selectedDay,
      title: 'Gantt task',
      tag: 'Focused summary',
      height: 80,
      color: Colors.teal,
      time: const TimeOfDay(hour: 9, minute: 0),
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
        theme: AppTheme.light,
        home: Scaffold(
          body: ScheduleTimeline(
            view: ScheduleTimelineView.gantt,
            selectedDay: selectedDay,
            entries: [entry],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final duration = find.byWidgetPredicate(
      (widget) => widget is Text && (widget.data?.contains('/ 1h') ?? false),
    );
    expect(duration, findsOneWidget);
    expect(_effectiveFontSize(tester, duration), greaterThanOrEqualTo(12));
  });
}

double _effectiveFontSize(WidgetTester tester, Finder finder) {
  final text = tester.widget<Text>(finder);
  return text.style?.fontSize ??
      DefaultTextStyle.of(tester.element(finder)).style.fontSize ??
      14;
}
