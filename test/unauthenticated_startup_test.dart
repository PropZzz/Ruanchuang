import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shixuzhipei/models/models.dart';
import 'package:shixuzhipei/services/api_client.dart';
import 'package:shixuzhipei/services/app_services.dart';
import 'package:shixuzhipei/services/data_service.dart';
import 'package:shixuzhipei/screens/team_page.dart';
import 'package:shixuzhipei/theme/app_theme.dart';
import 'package:shixuzhipei/screens/focus_page.dart';
import 'package:shixuzhipei/screens/smart_calendar_page.dart';
import 'package:shixuzhipei/widgets/emotion_quick_checkin_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(AppServices.resetForTests);

  testWidgets(
    'unauthenticated emotion loading does not escape into the global error dialog',
    (tester) async {
      AppServices.installTestOverrides(dataService: _UnauthorizedDataService());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: EmotionQuickCheckInCard()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets(
    'time crystal recommendation failure does not escape from the focus page',
    (tester) async {
      AppServices.installTestOverrides(
        dataService: _RecommendationsFailingDataService(),
      );

      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: const FocusPage()),
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 200));

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('focus-energy-status')), findsOneWidget);
    },
  );

  testWidgets(
    'parallel focus requests do not leave an unauthorized sibling unhandled',
    (tester) async {
      AppServices.installTestOverrides(
        dataService: _ParallelStartupFailureDataService(),
      );

      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: const FocusPage()),
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 200));

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'parallel team requests do not leave an unauthorized sibling unhandled',
    (tester) async {
      AppServices.installTestOverrides(
        dataService: _ParallelStartupFailureDataService(),
      );

      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: const TeamPage()),
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 200));

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('focus load failure keeps a local retry action visible', (
    tester,
  ) async {
    AppServices.installTestOverrides(
      dataService: _ParallelStartupFailureDataService(),
    );

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const FocusPage()),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 200));

    expect(find.byKey(const ValueKey('focus-load-retry')), findsOneWidget);
    expect(find.byKey(const ValueKey('focus-energy-status')), findsOneWidget);
  });

  testWidgets('calendar load failure keeps a local retry action visible', (
    tester,
  ) async {
    AppServices.installTestOverrides(
      dataService: _ParallelStartupFailureDataService(),
    );

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const SmartCalendarPage()),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 200));

    expect(find.byKey(const ValueKey('calendar-load-retry')), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-time-map')), findsOneWidget);
  });
}

class _UnauthorizedDataService implements DataService {
  ApiException get _unauthorized =>
      const ApiException('Unauthorized', statusCode: 401);

  @override
  Future<EmotionState> getEmotionState() async => throw _unauthorized;

  @override
  Future<List<EmotionCheckIn>> getEmotionCheckIns(DateTime day) async =>
      throw _unauthorized;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecommendationsFailingDataService implements DataService {
  ApiException get _unauthorized =>
      const ApiException('Unauthorized', statusCode: 401);

  @override
  Future<EnergyStatus> getEnergyStatus() async => const EnergyStatus(
    level: 'medium',
    status: '心流',
    description: '本地数据',
    batteryPercent: 85,
  );

  @override
  Future<EmotionType> getCurrentEmotion() async => EmotionType.stable;

  @override
  Future<EmotionState> getEmotionState() async => EmotionState.stable;

  @override
  Future<List<EmotionCheckIn>> getEmotionCheckIns(DateTime day) async =>
      const [];

  @override
  Future<List<ScheduleEntry>> getScheduleEntries() async => const [];

  @override
  Future<List<MicroTask>> getMicroTasks() async => throw _unauthorized;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ParallelStartupFailureDataService implements DataService {
  ApiException get _unauthorized =>
      const ApiException('Unauthorized', statusCode: 401);

  @override
  Future<EnergyStatus> getEnergyStatus() async => throw _unauthorized;

  @override
  Future<List<ScheduleEntry>> getScheduleEntries() async => throw _unauthorized;

  @override
  Future<List<TeamMemberCalendar>> getTeamCalendars(DateTime day) async =>
      throw _unauthorized;

  @override
  Future<List<TeamMember>> getTeamMembers() async => throw _unauthorized;

  @override
  Future<EmotionState> getEmotionState() async => EmotionState.stable;

  @override
  Future<List<EmotionCheckIn>> getEmotionCheckIns(DateTime day) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
