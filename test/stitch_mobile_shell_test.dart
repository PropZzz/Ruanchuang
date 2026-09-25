import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shixuzhipei/theme/app_theme.dart';
import 'package:shixuzhipei/widgets/stitch_mobile_scaffold.dart';

void main() {
  testWidgets('mobile scaffold renders Stitch chrome at phone width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: StitchMobileScaffold(
          title: 'Focus',
          pageLabel: 'Focus',
          child: const Text('content'),
          selectedIndex: 0,
          onSelect: (_) {},
        ),
      ),
    );

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
    expect(find.text('Focus'), findsWidgets);
  });

  testWidgets('mobile scaffold returns wide child at tablet width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: StitchMobileScaffold(
          title: 'Focus',
          pageLabel: 'Focus',
          child: const SizedBox(key: ValueKey('wide-child')),
          selectedIndex: 0,
          onSelect: (_) {},
        ),
      ),
    );

    expect(find.byKey(const ValueKey('wide-child')), findsOneWidget);
    expect(find.byKey(const ValueKey('stitch-mobile-header')), findsNothing);
  });
}
