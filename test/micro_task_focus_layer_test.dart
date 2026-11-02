import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shixuzhipei/models/models.dart';
import 'package:shixuzhipei/theme/app_theme.dart';
import 'package:shixuzhipei/widgets/micro_task_focus_layer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> openLayer(
    WidgetTester tester, {
    required Future<void> Function(int seconds) onComplete,
    Future<void> Function(int seconds)? onAbandon,
    void Function(MicroFocusOutcome? outcome)? onOutcome,
    DateTime Function()? now,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  final outcome = await showMicroTaskFocusLayer(
                    context,
                    task: MicroTask(
                      title: '整理发布清单',
                      tag: '发布',
                      minutes: 1,
                      priority: 5,
                    ),
                    totalMinutes: 1,
                    points: 7,
                    onComplete: onComplete,
                    onAbandon: onAbandon,
                    now: now,
                  );
                  onOutcome?.call(outcome);
                },
                child: const Text('打开专注'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开专注'));
    await tester.pumpAndSettle();
  }

  testWidgets('timer completes the task and close dismisses the layer', (
    tester,
  ) async {
    var completedSeconds = -1;
    var outcome = MicroFocusOutcome.abandoned;
    var fakeNow = DateTime(2026, 1, 1, 9);
    await openLayer(
      tester,
      onComplete: (seconds) async {
        completedSeconds = seconds;
      },
      onOutcome: (value) => outcome = value ?? MicroFocusOutcome.abandoned,
      now: () => fakeNow,
    );

    expect(find.byKey(const ValueKey('micro-focus-timer')), findsOneWidget);
    expect(find.text('01:00'), findsOneWidget);

    fakeNow = fakeNow.add(const Duration(seconds: 61));
    await tester.pump(const Duration(seconds: 61));
    await tester.pumpAndSettle();

    expect(completedSeconds, 60);
    expect(find.text('已完成'), findsOneWidget);
    expect(find.byKey(const ValueKey('micro-focus-close')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('micro-focus-close')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('micro-focus-timer')), findsNothing);
    expect(outcome, MicroFocusOutcome.completed);
  });

  testWidgets('early close can abandon without completing', (tester) async {
    var completed = false;
    var outcome = MicroFocusOutcome.completed;
    await openLayer(
      tester,
      onComplete: (seconds) async {
        completed = true;
      },
      onOutcome: (value) => outcome = value ?? MicroFocusOutcome.completed,
    );

    await tester.tap(find.byKey(const ValueKey('micro-focus-close')));
    await tester.pumpAndSettle();

    expect(find.text('结束专注？'), findsOneWidget);
    await tester.tap(find.text('放弃'));
    await tester.pumpAndSettle();

    expect(completed, isFalse);
    expect(outcome, MicroFocusOutcome.abandoned);
    expect(find.byKey(const ValueKey('micro-focus-timer')), findsNothing);
  });

  testWidgets('early close can mark the task done immediately', (tester) async {
    var completedSeconds = -1;
    var outcome = MicroFocusOutcome.abandoned;
    var fakeNow = DateTime(2026, 1, 1, 9);
    await openLayer(
      tester,
      onComplete: (seconds) async {
        completedSeconds = seconds;
      },
      onOutcome: (value) => outcome = value ?? MicroFocusOutcome.abandoned,
      now: () => fakeNow,
    );

    fakeNow = fakeNow.add(const Duration(seconds: 20));
    await tester.pump(const Duration(seconds: 20));
    await tester.tap(find.byKey(const ValueKey('micro-focus-close')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('标记完成'));
    await tester.pumpAndSettle();

    expect(completedSeconds, 20);
    expect(outcome, MicroFocusOutcome.completed);
    expect(find.byKey(const ValueKey('micro-focus-timer')), findsNothing);
  });
}
