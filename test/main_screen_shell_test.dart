import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shixuzhipei/screens/main_screen.dart';
import 'package:shixuzhipei/screens/profile_page.dart';
import 'package:shixuzhipei/services/app_services.dart';
import 'package:shixuzhipei/services/mock_data_service.dart';
import 'package:shixuzhipei/theme/app_theme.dart';
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
    expect(find.byKey(const ValueKey('shell-rail-expanded')), findsOneWidget);
    expect(find.byKey(const ValueKey('shell-rail-material')), findsOneWidget);
    tester.view.reset();
  });

  testWidgets('wide shell starts with a grouped expanded sidebar', (
    tester,
  ) async {
    await pumpShell(tester, const Size(1440, 900));

    final sidebarFinder = find.byKey(const ValueKey('shell-rail-expanded'));

    expect(tester.getSize(sidebarFinder).width, greaterThan(200));
    for (final group in [
      'nav_group_today',
      'nav_group_plan',
      'nav_group_collab',
      'nav_group_system',
    ]) {
      expect(find.byKey(ValueKey('shell-rail-group-$group')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('shell-rail-toggle')), findsOneWidget);
    expect(find.byTooltip('收起导航栏'), findsOneWidget);
    final focusLabel = find.byKey(const ValueKey('shell-rail-focus-label'));
    expect(focusLabel, findsOneWidget);
    expect(tester.getSize(focusLabel).width, greaterThan(0));
    tester.view.reset();
  });

  testWidgets(
    'wide shell marks reserved notifications and selection semantics',
    (tester) async {
      await pumpShell(tester, const Size(1440, 900));

      expect(find.byTooltip('通知（预留能力，待接入）'), findsOneWidget);

      final selectedFocus = find.byWidgetPredicate((widget) {
        if (widget is! Semantics) return false;
        return widget.properties.button == true &&
            widget.properties.selected == true &&
            widget.properties.label == '专注';
      });
      expect(selectedFocus, findsOneWidget);

      final unselectedTeam = find.byWidgetPredicate((widget) {
        if (widget is! Semantics) return false;
        return widget.properties.button == true &&
            widget.properties.selected == false &&
            widget.properties.label == '团队';
      });
      expect(unselectedTeam, findsOneWidget);
      tester.view.reset();
    },
  );

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

  testWidgets('narrow shell uses a full-width flat navigation bar', (
    tester,
  ) async {
    await pumpShell(tester, const Size(390, 844));

    expect(find.byType(NavigationBar), findsOneWidget);
    final materialFinder = find.byKey(const ValueKey('shell-bottom-material'));
    expect(materialFinder, findsOneWidget);
    final material = tester.widget<Material>(materialFinder);
    expect(material.color, AppTheme.light.colorScheme.surface);
    expect(material.borderRadius, BorderRadius.zero);
    final capsuleFinder = find.byKey(const ValueKey('shell-bottom-capsule'));
    expect(capsuleFinder, findsOneWidget);
    final materialRect = tester.getRect(materialFinder);
    expect(materialRect.width, 390);
    expect(materialRect.left, 0);
    expect(materialRect.right, 390);
    expect(materialRect.bottom, lessThanOrEqualTo(844));
    expect(tester.takeException(), isNull);
    expect(find.text('日程'), findsOneWidget);
    expect(find.text('微任务'), findsOneWidget);
    expect(find.text('团队'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
    tester.view.reset();
  });

  testWidgets('mobile shell uses Stitch chrome', (tester) async {
    await pumpShell(tester, const Size(390, 844));

    expect(find.byKey(const ValueKey('stitch-mobile-header')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('stitch-mobile-bottom-bar')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('stitch-mobile-nav-focus')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('stitch-mobile-nav-profile')),
      findsOneWidget,
    );
    tester.view.reset();
  });

  testWidgets('narrow iOS shell uses Cupertino tab navigation', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('zh'), Locale('en')],
        theme: AppTheme.light.copyWith(platform: TargetPlatform.iOS),
        home: const MainScreen(),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.byType(CupertinoTabBar), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    await tester.tap(find.text('团队'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(
      tester.widget<CupertinoTabBar>(find.byType(CupertinoTabBar)).currentIndex,
      3,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('secondary page keeps the mobile shell and primary navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
        home: const MainScreen(
          secondaryPage: Text('Secondary page'),
          secondaryTabIndex: 1,
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text('Secondary page'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    await tester.tap(find.text('专注'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text('Secondary page'), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(tester.takeException(), isNull);
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

  testWidgets('shell renders final state when animations are disabled', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
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
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: const MainScreen(),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    final switcher = tester.widget<AnimatedSwitcher>(
      find.byType(AnimatedSwitcher).first,
    );
    expect(switcher.duration, Duration.zero);
    expect(switcher.reverseDuration, Duration.zero);
    expect(find.byKey(const ValueKey('shell-rail-expanded')), findsOneWidget);
    expect(tester.takeException(), isNull);
    tester.view.reset();
  });
}
