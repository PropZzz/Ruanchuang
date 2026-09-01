import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shixuzhipei/screens/main_screen.dart';
import 'package:shixuzhipei/screens/profile_page.dart';
import 'package:shixuzhipei/services/app_services.dart';
import 'package:shixuzhipei/services/mock_data_service.dart';
import 'package:shixuzhipei/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('micro task header remains readable on a narrow window', (
    tester,
  ) async {
    AppServices.installTestOverrides(dataService: MockDataService());
    ProfilePage.globalNameNotifier.value = '测试用户';
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;

    try {
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: const MainScreen()),
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('shell-nav-micro')));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));

      expect(find.text('AI 填充'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      tester.view.reset();
      ProfilePage.globalNameNotifier.value = null;
      AppServices.resetForTests();
    }
  });
}
