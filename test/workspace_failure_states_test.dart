import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shixuzhipei/models/models.dart';
import 'package:shixuzhipei/screens/focus_page.dart';
import 'package:shixuzhipei/screens/goals_page.dart';
import 'package:shixuzhipei/screens/micro_task_page.dart';
import 'package:shixuzhipei/screens/profile_page.dart';
import 'package:shixuzhipei/screens/review_page.dart';
import 'package:shixuzhipei/screens/smart_calendar_page.dart';
import 'package:shixuzhipei/screens/team_page.dart';
import 'package:shixuzhipei/services/api_client.dart';
import 'package:shixuzhipei/services/app_services.dart';
import 'package:shixuzhipei/services/data_service.dart';
import 'package:shixuzhipei/services/remote_data_service.dart';
import 'package:shixuzhipei/theme/app_theme.dart';

void main() {
  tearDown(AppServices.resetForTests);
  final pages = <String, Widget Function()>{
    'focus': () => const FocusPage(),
    'calendar': () => const SmartCalendarPage(),
    'microtasks': () => const MicroTaskPage(),
    'team': () => const TeamPage(),
    'goals': () => const GoalsPage(),
    'review': () => const ReviewPage(),
  };
  final failures = <String, (Object, String)>{
    '401': (
      const ApiException('private response', statusCode: 401),
      'Sign in again from Profile',
    ),
    '409': (
      const ApiException('private response', statusCode: 409),
      'The data changed or conflicts.',
    ),
    '422': (
      const ApiException('private response', statusCode: 422),
      'The input was rejected.',
    ),
    '501': (
      const ApiException('private response', statusCode: 501),
      'This feature is not connected yet.',
    ),
    '503': (
      const ApiException('private response', statusCode: 503),
      'The service is temporarily unavailable.',
    ),
    'timeout': (TimeoutException('private response'), 'The request timed out.'),
    'offline': (
      RemoteUnavailableException('private response'),
      'Cannot reach the service.',
    ),
  };

  Future<void> open(WidgetTester tester, String name, Widget page) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: page));
    await tester.pump();
    if (name == 'review') {
      await tester.tap(find.text('Generate Report'));
      await tester.pump();
    }
  }

  for (final page in pages.entries) {
    for (final failure in failures.entries) {
      testWidgets(
        '${page.key} keeps ${failure.key} visible and recovers on retry',
        (tester) async {
          final service = _ControlledReads()..failure = failure.value.$1;
          AppServices.installTestOverrides(dataService: service);
          await open(tester, page.key, page.value());
          expect(find.byKey(ValueKey('${page.key}-load-retry')), findsNothing);
          if (!['goals', 'team'].contains(page.key)) {
            expect(find.byType(CircularProgressIndicator), findsWidgets);
          }
          service.ready.complete();
          await tester.pumpAndSettle();
          // Transient snackbars may expire; the local recovery control must stay.
          await tester.pump(const Duration(seconds: 6));
          await tester.pumpAndSettle();
          final retry = find.byKey(ValueKey('${page.key}-load-retry'));
          expect(retry, findsOneWidget);
          expect(find.textContaining(failure.value.$2), findsOneWidget);
          expect(find.textContaining('private response'), findsNothing);
          expect(tester.takeException(), isNull);

          service.failure = null;
          await tester.ensureVisible(retry);
          await tester.tap(retry);
          await tester.pumpAndSettle();
          expect(retry, findsNothing);
          expect(find.byType(CircularProgressIndicator), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('profile identifies partial data and can refresh it', (
    tester,
  ) async {
    final service = _ControlledReads()
      ..failure = const ApiException('private response', statusCode: 401);
    AppServices.installTestOverrides(dataService: service);
    await open(tester, 'profile', const ProfilePage());
    service.ready.complete();
    await tester.pumpAndSettle();
    final notice = find.byKey(const ValueKey('profile-partial-data-notice'));
    expect(notice, findsOneWidget);
    expect(find.textContaining('private response'), findsNothing);
    service.failure = null;
    await tester.ensureVisible(notice);
    await tester.tap(
      find.descendant(of: notice, matching: find.byType(IconButton)),
    );
    await tester.pumpAndSettle();
    expect(notice, findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _ControlledReads implements DataService {
  final ready = Completer<void>();
  Object? failure;
  Future<T> read<T>(T value) async {
    await ready.future;
    if (failure != null) throw failure!;
    return value;
  }

  @override
  Future<EnergyStatus> getEnergyStatus() => read(
    const EnergyStatus(
      level: 'medium',
      status: 'Ready',
      description: 'Available',
      batteryPercent: 70,
    ),
  );
  @override
  Future<List<ScheduleEntry>> getScheduleEntries() => read(<ScheduleEntry>[]);
  @override
  Future<List<MicroTask>> getMicroTasks() => read(<MicroTask>[]);
  @override
  Future<List<TeamMemberCalendar>> getTeamCalendars(DateTime day) =>
      read(<TeamMemberCalendar>[]);
  @override
  Future<List<TeamMember>> getTeamMembers() => read(<TeamMember>[]);
  @override
  Future<List<Goal>> getGoals() => read(<Goal>[]);
  @override
  Future<List<TaskEvent>> getTaskEvents(DateTime from, DateTime to) =>
      read(<TaskEvent>[]);
  @override
  Future<ReviewReport> getWeeklyReport(DateTime weekStart) => read(
    ReviewReport(
      weekStart: weekStart,
      weekEnd: weekStart.add(const Duration(days: 7)),
      startedCount: 0,
      completedCount: 0,
      completionRate: 0,
      plannedMinutesTotal: 0,
      actualMinutesTotal: 0,
      actualDurationBuckets: const {},
      delayAttribution: const {},
      suggestions: const [],
      tuning: const SchedulingTuning(),
    ),
  );
  @override
  Future<UserProfile> getUserProfile() =>
      read(const UserProfile(displayName: 'Test', status: 'Ready'));
  @override
  Future<EmotionType> getCurrentEmotion() async => EmotionType.stable;
  @override
  Future<EmotionState> getEmotionState() async => EmotionState.stable;
  @override
  Future<List<EmotionCheckIn>> getEmotionCheckIns(DateTime day) async => [];
  @override
  Future<SchedulingTuning> getSchedulingTuning() async =>
      const SchedulingTuning();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
