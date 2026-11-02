import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shixuzhipei/models/models.dart';
import 'package:shixuzhipei/screens/micro_task_page.dart';
import 'package:shixuzhipei/services/app_services.dart';
import 'package:shixuzhipei/services/local_data_service.dart';
import 'package:shixuzhipei/services/local_persistence/local_persistence.dart';
import 'package:shixuzhipei/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('next task follows P5 to P1 order and refills after completion', (
    tester,
  ) async {
    final service = LocalDataService.forPersistence(InMemoryLocalPersistence());
    final seeded = await service.getMicroTasks();
    for (final task in seeded) {
      await service.removeMicroTask(task);
    }
    for (final priority in [5, 4, 3, 2, 1]) {
      await service.addMicroTask(
        MicroTask(
          title: 'P$priority 任务',
          tag: '测试',
          minutes: 10,
          priority: priority,
        ),
      );
    }
    AppServices.installTestOverrides(dataService: service);
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;

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

      final nextCard = find.byKey(const ValueKey('micro-next-task'));
      expect(nextCard, findsOneWidget);
      expect(
        find.descendant(of: nextCard, matching: find.text('P5 任务')),
        findsOneWidget,
      );
      expect(find.text('P5 任务'), findsOneWidget);

      await tester.tap(
        find.descendant(of: nextCard, matching: find.text('完成')),
      );
      await tester.pumpAndSettle();

      final refilledCard = find.byKey(const ValueKey('micro-next-task'));
      expect(
        find.descendant(of: refilledCard, matching: find.text('P4 任务')),
        findsOneWidget,
      );
      expect(find.text('P5 任务'), findsNothing);

      await tester.tap(find.text('已完成 1'));
      await tester.pumpAndSettle();
      expect(find.text('P5 任务'), findsOneWidget);
    } finally {
      tester.view.reset();
      AppServices.resetForTests();
    }
  });
}
