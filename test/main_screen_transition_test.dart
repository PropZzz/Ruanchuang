import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shixuzhipei/screens/focus_page.dart';
import 'package:shixuzhipei/screens/main_screen.dart';
import 'package:shixuzhipei/screens/micro_task_page.dart';
import 'package:shixuzhipei/screens/profile_page.dart';
import 'package:shixuzhipei/screens/smart_calendar_page.dart';
import 'package:shixuzhipei/screens/team_page.dart';
import 'package:shixuzhipei/services/app_services.dart';
import 'package:shixuzhipei/services/mock_data_service.dart';
import 'package:shixuzhipei/theme/app_theme.dart';

void main() {
  setUp(() {
    AppServices.installTestOverrides(dataService: MockDataService());
    ProfilePage.globalNameNotifier.value = '测试用户';
  });

  tearDown(() {
    ProfilePage.globalNameNotifier.value = null;
    AppServices.resetForTests();
  });

  Future<void> pumpShell(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('zh'), Locale('en')],
        theme: AppTheme.light,
        home: const MainScreen(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('only initializes a destination when first selected', (
    tester,
  ) async {
    await pumpShell(tester);

    expect(find.byType(FocusPage), findsOneWidget);
    for (final type in [
      SmartCalendarPage,
      MicroTaskPage,
      TeamPage,
      ProfilePage,
    ]) {
      expect(find.byType(type, skipOffstage: false), findsNothing);
    }

    await tester.tap(find.text('微任务'));
    await tester.pumpAndSettle();
    expect(find.byType(MicroTaskPage), findsOneWidget);
    expect(find.byType(TeamPage, skipOffstage: false), findsNothing);
  });

  testWidgets('retains visited page state and mutes hidden tickers', (
    tester,
  ) async {
    await pumpShell(tester);
    final focusState = tester.state(find.byType(FocusPage));

    await tester.tap(find.text('微任务'));
    await tester.pumpAndSettle();
    final hiddenFocus = tester.element(
      find.byType(FocusPage, skipOffstage: false),
    );
    expect(TickerMode.of(hiddenFocus), isFalse);
    expect(TickerMode.of(tester.element(find.byType(MicroTaskPage))), isTrue);

    await tester.tap(find.text('专注'));
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(FocusPage)), same(focusState));
    expect(TickerMode.of(tester.element(find.byType(FocusPage))), isTrue);
  });

  testWidgets('resizing between mobile and desktop preserves page state', (
    tester,
  ) async {
    await pumpShell(tester);
    final focusState = tester.state(find.byType(FocusPage));
    tester.view.physicalSize = const Size(1440, 900);
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(FocusPage)), same(focusState));
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(FocusPage)), same(focusState));
    expect(tester.takeException(), isNull);
  });
}
