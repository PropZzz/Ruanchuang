import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shixuzhipei/screens/main_screen.dart';
import 'package:shixuzhipei/screens/profile_page.dart';
import 'package:shixuzhipei/services/app_services.dart';
import 'package:shixuzhipei/services/mock_data_service.dart';
import 'package:shixuzhipei/theme/app_theme.dart';
import 'package:shixuzhipei/widgets/glass_surface.dart';
import 'package:shixuzhipei/main.dart';

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

  testWidgets('wide shell omits the workspace title block', (tester) async {
    await pumpShell(tester, const Size(1440, 900));

    expect(
      find.byKey(const ValueKey('workspace-status-bar-material')),
      findsNothing,
    );
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byKey(const ValueKey('shell-rail-material')), findsOneWidget);
    tester.view.reset();
  });

  testWidgets('wide shell starts with an expanded navigation rail', (
    tester,
  ) async {
    await pumpShell(tester, const Size(1440, 900));

    final railFinder = find.byKey(const ValueKey('shell-rail-expanded'));
    final rail = tester.widget<NavigationRail>(railFinder);

    expect(rail.extended, isTrue);
    expect(tester.getSize(railFinder).width, 260);
    expect(find.byKey(const ValueKey('shell-rail-toggle')), findsOneWidget);
    expect(find.byTooltip('收起导航栏'), findsOneWidget);
    final focusLabel = find.byKey(const ValueKey('shell-rail-focus-label'));
    expect(focusLabel, findsOneWidget);
    expect(tester.getSize(focusLabel).width, greaterThan(0));
    tester.view.reset();
  });

  testWidgets('wide shell toggle expands the rail and reveals labels', (
    tester,
  ) async {
    await pumpShell(tester, const Size(1440, 900));

    await tester.tap(find.byKey(const ValueKey('shell-rail-toggle')));
    await tester.pumpAndSettle();

    final railFinder = find.byKey(const ValueKey('shell-rail-collapsed'));
    final rail = tester.widget<NavigationRail>(railFinder);

    expect(rail.extended, isFalse);
    expect(tester.getSize(railFinder).width, 76);
    expect(find.byTooltip('展开导航栏'), findsOneWidget);
    final focusLabel = find.byKey(const ValueKey('shell-rail-focus-label'));
    expect(tester.getSize(focusLabel), Size.zero);
    tester.view.reset();
  });

  testWidgets('narrow shell uses material navigation bar', (tester) async {
    await pumpShell(tester, const Size(390, 844));

    expect(find.byType(NavigationBar), findsOneWidget);
    final materialFinder = find.byKey(const ValueKey('shell-bottom-material'));
    expect(materialFinder, findsOneWidget);
    final material = tester.widget<GlassSurface>(materialFinder);
    expect(material.borderRadius, BorderRadius.circular(24));
    expect(material.margin, EdgeInsets.zero);
    expect(material.opacity, 0.9);
    expect(material.showShadow, isTrue);
    final capsuleFinder = find.byKey(const ValueKey('shell-bottom-capsule'));
    expect(capsuleFinder, findsOneWidget);
    final materialRect = tester.getRect(materialFinder);
    expect(materialRect.width, 366);
    expect(materialRect.left, 12);
    expect(materialRect.right, 378);
    expect(materialRect.bottom, lessThanOrEqualTo(834));
    expect(tester.takeException(), isNull);
    expect(find.text('日程'), findsOneWidget);
    expect(find.text('微任务'), findsOneWidget);
    expect(find.text('团队'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
    tester.view.reset();
  });

  testWidgets('tablet shell uses a compact navigation rail', (tester) async {
    await pumpShell(tester, const Size(768, 900));

    final railFinder = find.byKey(const ValueKey('shell-rail-compact'));
    expect(railFinder, findsOneWidget);
    expect(tester.widget<NavigationRail>(railFinder).extended, isFalse);
    expect(tester.getSize(railFinder).width, 88);
    expect(find.byType(NavigationBar), findsNothing);
    tester.view.reset();
  });

  test('text scale resolver preserves a 200 percent system scale', () {
    expect(resolveAppTextScale(2.0), 2.0);
  });
}
