import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shixuzhipei/models/models.dart';
import 'package:shixuzhipei/screens/emotion_page.dart';
import 'package:shixuzhipei/screens/goals_page.dart';
import 'package:shixuzhipei/screens/profile_page.dart';
import 'package:shixuzhipei/services/app_services.dart';
import 'package:shixuzhipei/services/data_service.dart';
import 'package:shixuzhipei/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _PageDataService data;

  setUp(() {
    data = _PageDataService();
    AppServices.installTestOverrides(dataService: data);
    ProfilePage.globalNameNotifier.value = '林知行';
    ProfilePage.globalAvatarNotifier.value = null;
  });

  tearDown(() {
    ProfilePage.globalNameNotifier.value = null;
    ProfilePage.globalAvatarNotifier.value = null;
    AppServices.resetForTests();
  });

  testWidgets(
    'profile keeps its dashboard hierarchy and pending status honest',
    (tester) async {
      await _pumpPage(tester, const ProfilePage(), 1440);

      expect(find.byKey(const ValueKey('profile-dashboard')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('profile-summary-metrics')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('profile-capability-ai-pending')),
        findsOneWidget,
      );
      expect(find.text('林知行'), findsOneWidget);
      expect(find.textContaining('待接入'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('profile settings use a bottom sheet on phone widths', (
    tester,
  ) async {
    await _pumpPage(tester, const ProfilePage(), 390);

    await tester.tap(find.byKey(const ValueKey('profile-settings-action')));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(
      find.byKey(const ValueKey('profile-settings-mobile-sheet')),
      findsOneWidget,
    );
    expect(find.text('设置'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('emotion page shows a check-in action and persists it', (
    tester,
  ) async {
    await _pumpPage(tester, const EmotionPage(), 390);

    expect(find.byKey(const ValueKey('emotion-overview')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('emotion-checkin-options')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('emotion-checkin-stable')));
    await tester.pumpAndSettle();

    expect(data.emotionCheckIns, hasLength(1));
    expect(data.emotionCheckIns.single.state, EmotionState.stable);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('emotion-today-records')),
      360,
    );
    expect(find.byKey(const ValueKey('emotion-today-records')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('emotion load errors leave a retry action instead of escaping', (
    tester,
  ) async {
    data.failEmotionReads = true;
    await _pumpPage(tester, const EmotionPage(), 390);

    expect(find.byKey(const ValueKey('emotion-load-error')), findsOneWidget);
    expect(find.byKey(const ValueKey('emotion-load-retry')), findsOneWidget);
    expect(tester.takeException(), isNull);

    data.failEmotionReads = false;
    await tester.tap(find.byKey(const ValueKey('emotion-load-retry')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('emotion-checkin-options')),
      findsOneWidget,
    );
  });

  testWidgets('goals open a draggable detail sheet and retain dependencies', (
    tester,
  ) async {
    data.goals.add(_sampleGoal());
    await _pumpPage(tester, const GoalsPage(), 390);

    expect(find.byKey(const ValueKey('goals-overview')), findsOneWidget);
    expect(find.byKey(const ValueKey('goals-upcoming-count')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('goal-card-goal-1')));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byKey(const ValueKey('goal-detail-sheet')), findsOneWidget);
    expect(find.text('先完成范围梳理'), findsOneWidget);
    expect(find.textContaining('依赖'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'new goal form saves through the data service from a phone sheet',
    (tester) async {
      await _pumpPage(tester, const GoalsPage(), 390);

      await tester.tap(find.byKey(const ValueKey('goals-add-action')));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byKey(const ValueKey('goal-add-form')), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('goal-add-title-input')),
        '完成产品原型',
      );
      await tester.tap(find.byKey(const ValueKey('goal-add-submit')));
      await tester.pumpAndSettle();

      expect(data.goals, hasLength(1));
      expect(data.goals.single.title, '完成产品原型');
      expect(data.goals.single.tasks, hasLength(5));
    },
  );

  testWidgets('the three pages stay renderable at phone and desktop widths', (
    tester,
  ) async {
    final pages = <Widget>[
      const ProfilePage(),
      const EmotionPage(),
      const GoalsPage(),
    ];

    for (final width in [390.0, 1440.0]) {
      for (final page in pages) {
        await _pumpPage(tester, page, width);
        expect(tester.takeException(), isNull, reason: 'width=$width');
      }
    }
  });
}

Future<void> _pumpPage(WidgetTester tester, Widget page, double width) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh', 'CN'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      theme: AppTheme.light,
      home: page,
    ),
  );
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
}

Goal _sampleGoal() => Goal(
  id: 'goal-1',
  title: '完成产品原型',
  due: DateTime.now().add(const Duration(days: 3)),
  priority: 2,
  tasks: const [
    GoalTask(
      id: 'goal-task-1',
      title: '先完成范围梳理',
      durationMinutes: 45,
      load: CognitiveLoad.medium,
      tag: '产品',
    ),
    GoalTask(
      id: 'goal-task-2',
      title: '整理交互方案',
      durationMinutes: 60,
      load: CognitiveLoad.high,
      tag: '产品',
      dependsOn: ['goal-task-1'],
    ),
  ],
);

class _PageDataService implements DataService {
  final List<Goal> goals = [];
  final List<EmotionCheckIn> emotionCheckIns = [];
  final List<ScheduleEntry> scheduleEntries = [];
  bool failEmotionReads = false;
  bool failGoalReads = false;

  @override
  Future<EmotionState> getEmotionState() async {
    if (failEmotionReads) throw StateError('emotion unavailable');
    final latest = emotionCheckIns.isEmpty ? null : emotionCheckIns.last;
    return latest?.state ?? EmotionState.stable;
  }

  @override
  Future<List<EmotionCheckIn>> getEmotionCheckIns(DateTime day) async {
    if (failEmotionReads) throw StateError('emotion unavailable');
    return emotionCheckIns
        .where((checkIn) => _sameDay(checkIn.at, day))
        .toList();
  }

  @override
  Future<void> addEmotionCheckIn(EmotionCheckIn checkIn) async {
    emotionCheckIns.add(checkIn);
  }

  @override
  Future<List<Goal>> getGoals() async {
    if (failGoalReads) throw StateError('goals unavailable');
    return List<Goal>.from(goals);
  }

  @override
  Future<void> upsertGoal(Goal goal) async {
    final id = goal.id.isEmpty ? 'created-goal' : goal.id;
    final stored = Goal(
      id: id,
      title: goal.title,
      due: goal.due,
      priority: goal.priority,
      tasks: goal.tasks,
    );
    final index = goals.indexWhere((item) => item.id == id);
    if (index == -1) {
      goals.add(stored);
    } else {
      goals[index] = stored;
    }
  }

  @override
  Future<void> deleteGoal(String goalId) async {
    goals.removeWhere((goal) => goal.id == goalId);
  }

  @override
  Future<List<ScheduleEntry>> getScheduleEntries() async =>
      List<ScheduleEntry>.from(scheduleEntries);

  @override
  Future<UserProfile> getUserProfile() async =>
      const UserProfile(displayName: '林知行', status: '本地模式');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
