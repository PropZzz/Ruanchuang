import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shixuzhipei/models/models.dart';
import 'package:shixuzhipei/theme/app_theme.dart';
import 'package:shixuzhipei/widgets/schedule_timeline.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final day = DateTime(2026, 9, 1);

  Widget host({
    List<ScheduleEntry> entries = const [],
    Set<ScheduleTimelineField> fields = const {
      ScheduleTimelineField.time,
      ScheduleTimelineField.tag,
      ScheduleTimelineField.status,
    },
    ValueChanged<ScheduleEntry>? onDelete,
  }) {
    return MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: ScheduleTimeline(
          view: ScheduleTimelineView.day,
          selectedDay: day,
          entries: entries,
          visibleFields: fields,
          statusByTaskId: const {'task-1': '进行中'},
          onDelete: onDelete,
        ),
      ),
    );
  }

  testWidgets('timeline renders event metadata and delete action', (
    tester,
  ) async {
    var deleted = false;
    final entry = ScheduleEntry(
      id: 'task-1',
      day: day,
      title: 'Architecture design',
      tag: 'Deep Work',
      height: 96,
      color: Colors.teal,
      time: const TimeOfDay(hour: 9, minute: 0),
    );

    await tester.pumpWidget(
      host(entries: [entry], onDelete: (_) => deleted = true),
    );
    await tester.pumpAndSettle();

    expect(find.text('Architecture design'), findsOneWidget);
    expect(find.text('Deep Work'), findsOneWidget);
    expect(find.text('进行中'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('schedule-timeline-track')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('schedule-entry-delete')));
    expect(deleted, isTrue);
  });

  testWidgets('timeline shows empty state', (tester) async {
    await tester.pumpWidget(host());
    expect(find.text('暂无日程'), findsOneWidget);
  });

  testWidgets('day timeline keeps minimum readable track width', (
    tester,
  ) async {
    final entry = ScheduleEntry(
      day: day,
      title: 'Task',
      tag: '',
      height: 80,
      color: Colors.teal,
      time: const TimeOfDay(hour: 8, minute: 0),
    );
    await tester.pumpWidget(host(entries: [entry]));
    await tester.pumpAndSettle();

    final track = tester.widget<ConstrainedBox>(
      find.byKey(const ValueKey('schedule-timeline-track')),
    );
    expect(track.constraints.minWidth, greaterThanOrEqualTo(760));
  });

  testWidgets('gantt groups the selected week into positioned day tracks', (
    tester,
  ) async {
    final entry = ScheduleEntry(
      id: 'gantt-1',
      day: day,
      title: 'Gantt task',
      tag: 'Planning',
      height: 80,
      color: Colors.teal,
      time: const TimeOfDay(hour: 9, minute: 0),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ScheduleTimeline(
            view: ScheduleTimelineView.gantt,
            selectedDay: day,
            entries: [entry],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('schedule-timeline-gantt-track')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('schedule-timeline-gantt-day-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('schedule-timeline-gantt-day-6')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('schedule-timeline-gantt-bar-gantt-1')),
      findsOneWidget,
    );
  });

  testWidgets('month summary keeps visible event metadata', (tester) async {
    final entry = ScheduleEntry(
      id: 'month-1',
      day: day,
      title: 'Month task',
      tag: 'Planning',
      height: 80,
      color: Colors.teal,
      time: const TimeOfDay(hour: 9, minute: 0),
      reminderMinutesBefore: 15,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ScheduleTimeline(
            view: ScheduleTimelineView.month,
            selectedDay: day,
            entries: [entry],
            visibleFields: const {
              ScheduleTimelineField.time,
              ScheduleTimelineField.tag,
              ScheduleTimelineField.reminder,
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Month task'), findsOneWidget);
    expect(find.text('Planning'), findsOneWidget);
    expect(find.text('15m'), findsOneWidget);
  });
}
