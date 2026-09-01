import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
<<<<<<< HEAD
import 'package:shixuzhipei/theme/app_theme.dart';
import 'package:shixuzhipei/widgets/glass_surface.dart';

void main() {
  test('light and dark themes expose the approved semantic tokens', () {
    final light = AppTheme.light;
    final dark = AppTheme.dark;

    expect(light.scaffoldBackgroundColor, AppThemeTokens.canvasLight);
    expect(light.colorScheme.primary, AppThemeTokens.actionLight);
    expect(light.colorScheme.tertiary, AppThemeTokens.recoveryLight);
    expect(light.colorScheme.error, AppThemeTokens.riskLight);

    expect(dark.scaffoldBackgroundColor, AppThemeTokens.canvasDark);
    expect(dark.colorScheme.primary, AppThemeTokens.actionDark);
    expect(dark.colorScheme.tertiary, AppThemeTokens.recoveryDark);
    expect(dark.colorScheme.error, AppThemeTokens.riskDark);
  });

  test('themes use material 3 and keep readable body text sizing', () {
    final theme = AppTheme.light;

    expect(theme.useMaterial3, isTrue);
    expect(theme.textTheme.bodyMedium?.fontSize, greaterThanOrEqualTo(12));
    expect(theme.cardTheme.shape, isA<RoundedRectangleBorder>());
  });

  testWidgets(
    'window tones stay distinct while glass surfaces keep semantics',
    (tester) async {
      Color? focus;
      Color? schedule;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) {
              focus = AppWindowTones.canvas(context, AppWindowTone.focus);
              schedule = AppWindowTones.canvas(context, AppWindowTone.schedule);
              return const GlassSurface(child: Text('surface'));
            },
          ),
        ),
      );
      expect(focus, isNotNull);
      expect(schedule, isNotNull);
      expect(focus, isNot(schedule));
      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(find.text('surface'), findsOneWidget);
    },
  );

  testWidgets('motion tokens honor reduced-motion preference', (tester) async {
    Duration? resolved;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) {
              resolved = AppMotion.resolve(
                context,
                const Duration(milliseconds: 260),
              );
              return const SizedBox();
            },
=======
import 'package:shixuzhipei/ui/app_theme.dart';
import 'package:shixuzhipei/widgets/workbench_surface.dart';

void main() {
  testWidgets('workbench theme uses the scheduling semantic colors', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: const Scaffold()),
    );

    final scheme = Theme.of(tester.element(find.byType(Scaffold))).colorScheme;
    expect(scheme.primary, const Color(0xFF153F45));
    expect(scheme.error, const Color(0xFFA8493B));
    expect(
      Theme.of(tester.element(find.byType(Scaffold))).cardTheme.shape,
      isA<RoundedRectangleBorder>(),
    );
  });

  testWidgets('dark theme uses the dark semantic colors', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.dark(), home: const Scaffold()),
    );

    final scheme = Theme.of(tester.element(find.byType(Scaffold))).colorScheme;
    expect(scheme.primary, const Color(0xFFA8D7C9));
    expect(scheme.error, const Color(0xFFE18B7D));
  });

  testWidgets('workbench surface renders a bordered title and child', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const WorkbenchSurface(title: '今日概览', child: Text('内容')),
      ),
    );

    expect(find.text('今日概览'), findsOneWidget);
    expect(find.text('内容'), findsOneWidget);
    expect(find.byType(WorkbenchSurface), findsOneWidget);

    final container = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(WorkbenchSurface),
            matching: find.byType(Container),
          )
          .first,
    );
    final decoration = container.decoration! as BoxDecoration;
    expect(decoration.border, isNotNull);
    expect(decoration.borderRadius, BorderRadius.circular(8));
  });

  testWidgets('workbench surface without title omits the heading', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const WorkbenchSurface(child: Text('内容')),
      ),
    );

    expect(find.text('内容'), findsOneWidget);
    expect(find.byType(WorkbenchSectionHeader), findsNothing);
  });

  testWidgets('section header renders title and trailing action', (
    tester,
  ) async {
    var tapped = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: WorkbenchSectionHeader(
            title: '冲突提醒',
            trailing: IconButton(
              key: const Key('section-action'),
              tooltip: '查看全部',
              icon: const Icon(Icons.chevron_right),
              onPressed: () => tapped++,
            ),
>>>>>>> d9a13f017b1d6e2337be5f4fe471d93a1f14c33d
          ),
        ),
      ),
    );
<<<<<<< HEAD
    expect(resolved, Duration.zero);
=======

    expect(find.text('冲突提醒'), findsOneWidget);
    expect(find.byTooltip('查看全部'), findsOneWidget);
    await tester.tap(find.byKey(const Key('section-action')));
    expect(tapped, 1);
  });

  testWidgets('metric renders label, value and supporting text', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: WorkbenchMetric(
            label: '完成率',
            value: '82%',
            supportingText: '较上周 +6%',
            status: WorkbenchStatus.success,
          ),
        ),
      ),
    );

    expect(find.text('完成率'), findsOneWidget);
    expect(find.text('82%'), findsOneWidget);
    expect(find.text('较上周 +6%'), findsOneWidget);
  });

  testWidgets('empty state renders message and action button', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: WorkbenchEmptyState(
            icon: Icons.event_busy,
            title: '今天没有日程',
            message: '添加日程后会显示在这里',
            actionLabel: '添加日程',
            actionTooltip: '创建新的日程',
            onAction: () => tapped++,
          ),
        ),
      ),
    );

    expect(find.text('今天没有日程'), findsOneWidget);
    expect(find.text('添加日程后会显示在这里'), findsOneWidget);
    expect(find.byIcon(Icons.event_busy), findsOneWidget);
    await tester.tap(find.byTooltip('创建新的日程'));
    expect(tapped, 1);
  });

  testWidgets('status badge pairs icon and text with the success color', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: WorkbenchStatusBadge(
            status: WorkbenchStatus.success,
            label: '可执行',
          ),
        ),
      ),
    );

    expect(find.text('可执行'), findsOneWidget);
    final icon = tester.widget<Icon>(find.byIcon(Icons.check_circle_outline));
    final scheme = Theme.of(
      tester.element(find.byType(WorkbenchStatusBadge)),
    ).colorScheme;
    expect(icon.color, scheme.secondary);
  });

  testWidgets('status badge uses the risk color for risk status', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: WorkbenchStatusBadge(
            status: WorkbenchStatus.risk,
            label: '冲突',
          ),
        ),
      ),
    );

    final icon = tester.widget<Icon>(find.byIcon(Icons.error_outline));
    final scheme = Theme.of(
      tester.element(find.byType(WorkbenchStatusBadge)),
    ).colorScheme;
    expect(icon.color, scheme.error);
>>>>>>> d9a13f017b1d6e2337be5f4fe471d93a1f14c33d
  });
}
