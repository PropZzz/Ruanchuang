import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shixuzhipei/screens/bluetooth_page.dart';
import 'package:shixuzhipei/screens/debug/diagnostics_page.dart';
import 'package:shixuzhipei/screens/device_detail_page.dart';
import 'package:shixuzhipei/screens/integrations_page.dart';
import 'package:shixuzhipei/screens/review_page.dart';
import 'package:shixuzhipei/services/app_services.dart';
import 'package:shixuzhipei/services/local_data_service.dart';
import 'package:shixuzhipei/services/local_persistence/local_persistence.dart';
import 'package:shixuzhipei/theme/app_theme.dart';

Widget _app(Widget home) {
  return MaterialApp(
    locale: const Locale('zh', 'CN'),
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    supportedLocales: const [Locale('zh', 'CN')],
    theme: AppTheme.light,
    home: home,
  );
}

class _EmptyBluetoothDevice extends BluetoothDevice {
  _EmptyBluetoothDevice() : super(remoteId: DeviceIdentifier('test-device'));

  @override
  String get platformName => '测试传感器';

  @override
  Future<List<BluetoothService>> discoverServices({
    bool subscribeToServicesChanged = true,
    int timeout = 15,
  }) async => const [];

  @override
  Stream<BluetoothConnectionState> get connectionState =>
      Stream<BluetoothConnectionState>.value(
        BluetoothConnectionState.disconnected,
      );
}

void main() {
  setUp(() {
    AppServices.resetForTests();
    AppServices.logStore.clear();
  });

  tearDown(() {
    AppServices.resetForTests();
    AppServices.logStore.clear();
  });

  testWidgets('review keeps its report sections legible on a phone width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final local = LocalDataService.forPersistence(InMemoryLocalPersistence());
    AppServices.installTestOverrides(dataService: local);

    await tester.pumpWidget(
      _app(ReviewPage(clock: () => DateTime(2026, 8, 6))),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('review-metrics')), findsOneWidget);
    expect(find.byKey(const Key('review-rescue-history')), findsOneWidget);
    expect(find.text('暂无报告，可以先模拟或生成。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'integrations starts with an honest empty preview and parses ICS',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final local = LocalDataService.forPersistence(InMemoryLocalPersistence());
      AppServices.installTestOverrides(dataService: local);

      await tester.pumpWidget(_app(const IntegrationsPage()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('integrations-preview')), findsOneWidget);
      expect(find.text('等待解析'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('integrations-import')))
            .onPressed,
        isNull,
      );

      await tester.enterText(
        find.byKey(const Key('integrations-raw-input')),
        'BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:demo-review\n'
        'SUMMARY:项目评审\nDTSTART:20260806T140000\n'
        'DURATION:PT45M\nEND:VEVENT\nEND:VCALENDAR',
      );
      await tester.tap(find.byKey(const Key('integrations-parse')));
      await tester.pumpAndSettle();

      expect(find.text('demo-review'), findsOneWidget);
      expect(find.text('项目评审'), findsOneWidget);
      expect(find.text('ICS'), findsNWidgets(2));
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('integrations-import')))
            .onPressed,
        isNotNull,
      );

      final entriesBeforeImport = await local.getScheduleEntries();
      await tester.tap(find.byKey(const Key('integrations-import')));
      await tester.pumpAndSettle();
      final imported = await local.getScheduleEntries();
      expect(imported, hasLength(entriesBeforeImport.length + 1));
      expect(imported.where((entry) => entry.title == '项目评审'), hasLength(1));
      expect(find.text('已导入 1 条 ICS 日程。'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('integrations-raw-input')),
        'no event time here',
      );
      await tester.tap(find.byKey(const Key('integrations-parse')));
      await tester.pumpAndSettle();
      expect(find.text('未识别到时间信息。'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('integrations-raw-input')))
            .controller
            ?.text,
        'no event time here',
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('integrations-import')))
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('bluetooth scan surface names the real result state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_app(const BluetoothPage()));
    await tester.pumpAndSettle();

    expect(find.text('周边 BLE 设备'), findsOneWidget);
    expect(find.text('未找到设备。'), findsOneWidget);
    expect(find.byTooltip('开始扫描'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('device details surfaces its service list on a phone width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _app(DeviceDetailPage(device: _EmptyBluetoothDevice())),
    );
    await tester.pumpAndSettle();

    expect(find.text('测试传感器'), findsNWidgets(2));
    expect(find.text('设备服务'), findsOneWidget);
    expect(find.text('尚无可用服务。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('diagnostics filters log entries by level and text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    AppServices.installTestOverrides(
      dataService: LocalDataService.forPersistence(InMemoryLocalPersistence()),
    );
    AppServices.logStore.info('sync', 'calendar updated', data: {'count': 4});
    AppServices.logStore.error('bluetooth', 'connection failed');

    await tester.pumpWidget(_app(const DiagnosticsPage()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('diagnostics-log-search')), findsOneWidget);
    expect(find.byKey(const Key('diagnostics-level-filter')), findsOneWidget);
    expect(find.textContaining('calendar updated'), findsOneWidget);
    expect(find.textContaining('connection failed'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('diagnostics-log-search')),
      'calendar',
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('calendar updated'), findsOneWidget);
    expect(find.textContaining('connection failed'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
