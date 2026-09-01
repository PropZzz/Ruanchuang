import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shixuzhipei/screens/main_screen.dart';
import 'package:shixuzhipei/screens/profile_page.dart';
import 'package:shixuzhipei/services/app_services.dart';
import 'package:shixuzhipei/services/mock_data_service.dart';
import 'package:shixuzhipei/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppServices.installTestOverrides(dataService: MockDataService());
    ProfilePage.globalNameNotifier.value = '测试用户';
  });

  tearDown(() {
    ProfilePage.globalNameNotifier.value = null;
    AppServices.resetForTests();
  });

  Future<void> pumpShell(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('zh'), Locale('en')],
        theme: AppTheme.light,
        home: const MainScreen(),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
  }

  testWidgets('wide shell exposes workspace status bar and navigation rail', (
    tester,
  ) async {
    await pumpShell(tester, const Size(1440, 900));

    expect(find.byKey(const ValueKey('workspace-status-bar')), findsOneWidget);
    expect(find.byType(NavigationRail), findsOneWidget);
    tester.view.reset();
  });

  testWidgets('wide shell starts with a collapsed icon-only navigation rail', (
    tester,
  ) async {
    await pumpShell(tester, const Size(1440, 900));

    final railFinder = find.byKey(const ValueKey('shell-rail-collapsed'));
    final rail = tester.widget<NavigationRail>(railFinder);

    expect(rail.extended, isFalse);
    expect(tester.getSize(railFinder).width, 76);
    expect(find.byKey(const ValueKey('shell-rail-toggle')), findsOneWidget);
    expect(find.byTooltip('展开导航栏'), findsOneWidget);
    final focusLabel = find.byKey(const ValueKey('shell-rail-focus-label'));
    expect(focusLabel, findsOneWidget);
    expect(tester.getSize(focusLabel), Size.zero);
    tester.view.reset();
  });

  testWidgets('wide shell toggle expands the rail and reveals labels', (
    tester,
  ) async {
    await pumpShell(tester, const Size(1440, 900));

    await tester.tap(find.byKey(const ValueKey('shell-rail-toggle')));
    await tester.pumpAndSettle();

    final railFinder = find.byKey(const ValueKey('shell-rail-expanded'));
    final rail = tester.widget<NavigationRail>(railFinder);

    expect(rail.extended, isTrue);
    expect(tester.getSize(railFinder).width, 248);
    expect(find.byTooltip('收起导航栏'), findsOneWidget);
    expect(
      find.descendant(of: railFinder, matching: find.text('专注')),
      findsOneWidget,
    );
    tester.view.reset();
  });

  testWidgets('narrow shell uses material navigation bar', (tester) async {
    await pumpShell(tester, const Size(390, 844));

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byKey(const ValueKey('workspace-status-bar')), findsOneWidget);
    tester.view.reset();
  });

  testWidgets('narrow shell floats the navigation bar in a pill', (
    tester,
  ) async {
    await pumpShell(tester, const Size(390, 844));

    final shell = tester.widget<Material>(
      find.byKey(const ValueKey('shell-floating-navigation')),
    );
    expect(shell.shape, isA<StadiumBorder>());
    expect(tester.takeException(), isNull);
    tester.view.reset();
  });
}
