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

  Future<void> pumpShell(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    final previousOnError = FlutterError.onError;
    final overflowErrors = <String>[];
    FlutterError.onError = (details) {
      final message = details.exceptionAsString();
      if (message.toLowerCase().contains('overflow')) {
        overflowErrors.add(message);
      }
      previousOnError?.call(details);
    };
    try {
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
    } finally {
      FlutterError.onError = previousOnError;
    }
    expect(overflowErrors, isEmpty, reason: 'width=$width');
  }

  void expectNoShellDiagnostics(WidgetTester tester, double width) {
    expect(tester.takeException(), isNull, reason: 'width=$width');
    final diagnosticText = find.byWidgetPredicate((widget) {
      if (widget is! Text) return false;
      final value = widget.data?.toUpperCase() ?? '';
      return value.contains('<<<<<<<') ||
          value.contains('=======') ||
          value.contains('>>>>>>>');
    });
    expect(
      diagnosticText,
      findsNothing,
      reason: 'shell contains a conflict marker or overflow diagnostic',
    );
  }

  testWidgets('workbench remains renderable across supported breakpoints', (
    tester,
  ) async {
    for (final width in [375.0, 768.0, 1024.0, 1440.0]) {
      await pumpShell(tester, width);
      expectNoShellDiagnostics(tester, width);

      if (width >= 720) {
        expect(find.byType(NavigationRail), findsOneWidget);
        expect(find.byType(NavigationBar), findsNothing);
      } else {
        expect(find.byType(NavigationBar), findsOneWidget);
        expect(find.byType(NavigationRail), findsNothing);
      }
    }
    tester.view.reset();
  });

  testWidgets('wide shell expands the navigation rail by default', (
    tester,
  ) async {
    await pumpShell(tester, 1440);

    final railFinder = find.byKey(const ValueKey('shell-rail-expanded'));
    expect(railFinder, findsOneWidget);
    expect(tester.widget<NavigationRail>(railFinder).extended, isTrue);
    expectNoShellDiagnostics(tester, 1440);
    tester.view.reset();
  });

  testWidgets('compact shell uses a navigation bar at 390 pixels', (
    tester,
  ) async {
    await pumpShell(tester, 390);

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expectNoShellDiagnostics(tester, 390);
    tester.view.reset();
  });
}
