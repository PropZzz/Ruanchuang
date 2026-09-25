import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shixuzhipei/models/models.dart';
import 'package:shixuzhipei/screens/micro_task_page.dart';
import 'package:shixuzhipei/screens/team_page.dart';
import 'package:shixuzhipei/services/app_services.dart';
import 'package:shixuzhipei/services/local_data_service.dart';
import 'package:shixuzhipei/services/local_persistence/local_persistence.dart';
import 'package:shixuzhipei/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final width in [390.0, 719.0, 720.0, 1440.0]) {
    testWidgets('microtask layout fits at ${width.toInt()}px', (tester) async {
      final service = await _localService();
      await service.addMicroTask(
        MicroTask(
          title: '修复移动端导航栏的长标题任务不会挤压操作控件',
          tag: '跨团队评审与发布',
          minutes: 20,
          priority: 1,
        ),
      );
      AppServices.installTestOverrides(dataService: service);
      _setSurface(tester, width);

      try {
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('zh', 'CN'),
            supportedLocales: const [Locale('zh', 'CN')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: AppTheme.light,
            home: const MicroTaskPage(),
          ),
        );
        await tester.pumpAndSettle();

        final layout = _layoutFor(width);
        expect(
          find.byKey(ValueKey('microtasks-layout-$layout')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      } finally {
        _resetSurface(tester);
        AppServices.resetForTests();
      }
    });

    testWidgets('team layout fits at ${width.toInt()}px', (tester) async {
      final service = await _localService();
      for (var i = 0; i < 4; i++) {
        await service.upsertTeamMember(
          TeamMemberCalendar(
            memberId: 'member-$i',
            displayName: '协作成员名称较长$i',
            role: '产品与算法协同工程师',
            energy: EnergyTier.high,
            permission: TeamSharePermission.details,
            busy: const [],
          ),
        );
      }
      AppServices.installTestOverrides(dataService: service);
      _setSurface(tester, width);

      try {
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('zh', 'CN'),
            supportedLocales: const [Locale('zh', 'CN')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: AppTheme.light,
            home: const TeamPage(),
          ),
        );
        await tester.pumpAndSettle();

        final layout = _layoutFor(width);
        expect(find.byKey(ValueKey('team-layout-$layout')), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        _resetSurface(tester);
        AppServices.resetForTests();
      }
    });
  }

  testWidgets('microtask creation uses a bottom sheet on mobile', (
    tester,
  ) async {
    AppServices.installTestOverrides(dataService: await _localService());
    _setSurface(tester, 390);

    try {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: AppTheme.light,
          home: const MicroTaskPage(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加微任务'));
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      _resetSurface(tester);
      AppServices.resetForTests();
    }
  });

  testWidgets('adding a team member uses a bottom sheet on mobile', (
    tester,
  ) async {
    AppServices.installTestOverrides(dataService: await _localService());
    _setSurface(tester, 390);

    try {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: AppTheme.light,
          home: const TeamPage(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PopupMenuItem<String>).first);
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      _resetSurface(tester);
      AppServices.resetForTests();
    }
  });
}

String _layoutFor(double width) {
  if (width < 720) return 'mobile';
  if (width < 1200) return 'tablet';
  return 'desktop';
}

Future<LocalDataService> _localService() async {
  final service = LocalDataService.forPersistence(InMemoryLocalPersistence());
  await service.getMicroTasks();
  return service;
}

void _setSurface(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
}

void _resetSurface(WidgetTester tester) {
  tester.view.reset();
}
