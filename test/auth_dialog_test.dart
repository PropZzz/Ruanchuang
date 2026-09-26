import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shixuzhipei/models/models.dart';
import 'package:shixuzhipei/screens/auth_dialog.dart';
import 'package:shixuzhipei/services/api_client.dart';
import 'package:shixuzhipei/services/app_services.dart';
import 'package:shixuzhipei/services/data_service.dart';
import 'package:shixuzhipei/services/local_data_service.dart';
import 'package:shixuzhipei/services/local_persistence/local_persistence.dart';
import 'package:shixuzhipei/theme/app_theme.dart';

class _AuthDataService implements DataService {
  UserAccount? currentUser;
  String? registeredDisplayName;
  Object? loginError;
  int guestSessionStarts = 0;

  @override
  Future<void> startGuestSession() async {
    guestSessionStarts++;
    currentUser = null;
  }

  @override
  Future<UserAccount?> getCurrentUser() async => currentUser;

  @override
  Future<bool> login(String account, String password) async {
    final error = loginError;
    if (error != null) throw error;
    if (password.length < 6) return false;
    currentUser = UserAccount(contactAddress: account, displayName: '登录用户');
    return true;
  }

  @override
  Future<bool> registerAccount({
    required String username,
    required String displayName,
    required String password,
  }) async {
    registeredDisplayName = displayName;
    currentUser = UserAccount(
      contactAddress: username,
      displayName: displayName,
    );
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late LocalDataService local;

  setUp(() {
    AppServices.resetForTests();
    local = LocalDataService.forPersistence(InMemoryLocalPersistence());
    AppServices.installTestOverrides(dataService: local);
  });

  tearDown(() => AppServices.resetForTests());

  test('local registration returns with the selected display name', () async {
    final success = await local.registerAccount(
      username: 'alice@example.com',
      displayName: '知行',
      password: 'secret123',
    );

    expect(success, isTrue);
    expect((await local.getCurrentUser())?.displayName, '知行');
  });

  Future<void> pumpAuth(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: AuthDialog(onAuthSuccess: () {}),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('registration stores the nickname entered by the user', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final authService = _AuthDataService();
    AppServices.installTestOverrides(dataService: authService);
    var authenticated = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: AuthDialog(onAuthSuccess: () => authenticated = true),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('注册').first);
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'alice@example.com');
    await tester.enterText(fields.at(1), '知行');
    await tester.enterText(fields.at(2), 'secret123');
    await tester.enterText(fields.at(3), 'secret123');
    await tester.tap(find.widgetWithText(FilledButton, '注册'));
    for (var frame = 0; frame < 20 && !authenticated; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(authenticated, isTrue);
    expect(authService.registeredDisplayName, '知行');
    expect(authService.currentUser?.displayName, '知行');
  });

  testWidgets('authentication surface fits a narrow phone viewport', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpAuth(tester);

    final bounds = tester.getRect(
      find.byKey(const ValueKey('auth-dialog-material')),
    );
    expect(bounds.left, greaterThanOrEqualTo(0));
    expect(bounds.right, lessThanOrEqualTo(390));
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows the backend credential error on login failure', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final authService = _AuthDataService()
      ..loginError = const ApiException(
        '{"detail":"Invalid credentials"}',
        statusCode: 401,
      );
    AppServices.installTestOverrides(dataService: authService);
    await pumpAuth(tester);

    await tester.enterText(
      find.byKey(const ValueKey('auth-account-input')),
      'alice@example.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('auth-password-input')),
      'secret123',
    );
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    for (var frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text('手机号/邮箱或密码不正确').evaluate().isNotEmpty) break;
    }

    expect(find.text('手机号/邮箱或密码不正确'), findsOneWidget);
  });

  testWidgets('guest entry clears the current account session', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final authService = _AuthDataService()
      ..currentUser = const UserAccount(
        contactAddress: 'alice@example.com',
        displayName: 'Alice',
      );
    AppServices.installTestOverrides(dataService: authService);
    var authenticated = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: AuthDialog(onAuthSuccess: () => authenticated = true),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('游客身份体验'));
    for (var frame = 0; frame < 10 && !authenticated; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(authenticated, isTrue);
    expect(authService.guestSessionStarts, 1);
    expect(authService.currentUser, isNull);
  });
}
