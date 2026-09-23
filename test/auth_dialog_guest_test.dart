import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shixuzhipei/screens/auth_dialog.dart';
import 'package:shixuzhipei/services/app_services.dart';
import 'package:shixuzhipei/services/data_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(AppServices.resetForTests);

  testWidgets('guest action explicitly switches the data service to guest', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final service = _GuestDataService();
    var completed = false;
    AppServices.installTestOverrides(dataService: service);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(0.5)),
          child: child!,
        ),
        home: AuthDialog(onAuthSuccess: () => completed = true),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continue as Guest'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    expect(service.continueAsGuestCalls, 1);
    expect(completed, isTrue);
  });
}

class _GuestDataService implements DataService {
  int continueAsGuestCalls = 0;

  @override
  Future<void> continueAsGuest() async {
    continueAsGuestCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
