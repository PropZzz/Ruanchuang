import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
      MaterialApp(theme: AppTheme.light, home: const MainScreen()),
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
