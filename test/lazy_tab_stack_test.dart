import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shixuzhipei/theme/app_theme.dart';
import 'package:shixuzhipei/widgets/lazy_tab_stack.dart';

void main() {
  late ValueNotifier<int> selection;
  late ValueNotifier<bool> reducedMotion;
  late List<int> builds;
  late List<Widget> pages;

  setUp(() {
    selection = ValueNotifier(0);
    reducedMotion = ValueNotifier(false);
    builds = [0, 0, 0];
    pages = List.generate(
      3,
      (i) => Builder(
        builder: (_) {
          builds[i]++;
          return SizedBox.expand(key: ValueKey('page-$i'));
        },
      ),
    );
  });

  tearDown(() {
    selection.dispose();
    reducedMotion.dispose();
  });

  Future<void> pumpTabs(WidgetTester tester, {bool rtl = false}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder(
          valueListenable: reducedMotion,
          builder: (context, reduced, _) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
            child: Directionality(
              textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
              child: ValueListenableBuilder(
                valueListenable: selection,
                builder: (_, index, _) => Material(
                  child: LazyTabStack(index: index, children: pages),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  double pageX(WidgetTester tester, int index) =>
      tester.getTopLeft(find.byKey(ValueKey('page-$index'))).dx;

  double opacity(WidgetTester tester) => tester
      .widget<FadeTransition>(
        find
            .descendant(
              of: find.byType(LazyTabStack),
              matching: find.byType(FadeTransition),
            )
            .first,
      )
      .opacity
      .value;

  testWidgets('initial page is visible without an entrance animation', (
    tester,
  ) async {
    await pumpTabs(tester);
    expect(builds, [1, 0, 0]);
    expect(pageX(tester, 0), 0);
    expect(opacity(tester), 1);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('transition moves toward rest without rebuilding page content', (
    tester,
  ) async {
    await pumpTabs(tester);
    selection.value = 1;
    await tester.pump();
    expect(pageX(tester, 1), 12);
    expect(opacity(tester), closeTo(0.8, 0.001));
    final buildsAfterSelection = List<int>.of(builds);

    await tester.pump(const Duration(milliseconds: 60));
    expect(pageX(tester, 1), inExclusiveRange(0, 12));
    expect(opacity(tester), inExclusiveRange(0.8, 1));
    await tester.pump(const Duration(milliseconds: 120));
    expect(pageX(tester, 1), 0);
    expect(opacity(tester), 1);
    expect(builds, buildsAfterSelection);

    selection.value = 0;
    await tester.pump();
    expect(pageX(tester, 0), -12);
    await tester.pumpAndSettle();
  });

  testWidgets(
    'rapid selection immediately targets the last tab and keeps state',
    (tester) async {
      await pumpTabs(tester);
      for (final index in [1, 2, 0, 2, 1]) {
        selection.value = index;
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 20));
        for (var i = 0; i < 3; i++) {
          expect(
            find.byKey(ValueKey('page-$i')),
            i == index ? findsOneWidget : findsNothing,
          );
        }
      }
      await tester.pump(AppMotion.tabSwitch);
      expect(pageX(tester, 1), 0);
      expect(opacity(tester), 1);
      expect(builds, [1, 1, 1]);
      expect(tester.binding.hasScheduledFrame, isFalse);
    },
  );

  testWidgets('reduced motion skips movement and fade on selection', (
    tester,
  ) async {
    reducedMotion.value = true;
    await pumpTabs(tester);
    selection.value = 1;
    await tester.pump();
    expect(pageX(tester, 1), 0);
    expect(opacity(tester), 1);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('enabling reduced motion finishes an in-flight transition', (
    tester,
  ) async {
    await pumpTabs(tester);
    selection.value = 1;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    reducedMotion.value = true;
    await tester.pump();
    expect(pageX(tester, 1), 0);
    expect(opacity(tester), 1);
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets(
    'hidden form retains its input but cannot receive keyboard focus',
    (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      pages = [
        TextField(focusNode: node),
        const Text('Second'),
        const Text('Third'),
      ];
      await pumpTabs(tester);
      await tester.enterText(find.byType(TextField), 'draft');
      expect(node.hasFocus, isTrue);
      selection.value = 1;
      await tester.pumpAndSettle();
      expect(node.hasFocus, isFalse);
      expect(node.canRequestFocus, isFalse);
      selection.value = 0;
      await tester.pumpAndSettle();
      expect(find.text('draft'), findsOneWidget);
      expect(node.canRequestFocus, isTrue);
    },
  );

  testWidgets('tab motion respects right-to-left navigation', (tester) async {
    await pumpTabs(tester, rtl: true);
    selection.value = 1;
    await tester.pump();
    expect(pageX(tester, 1), -12);
    await tester.pumpAndSettle();
    expect(pageX(tester, 1), 0);
  });
}
