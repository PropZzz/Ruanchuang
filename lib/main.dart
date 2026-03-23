import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_globals.dart';
import 'screens/main_screen.dart';
import 'services/app_services.dart';
import 'utils/app_strings.dart';

Future<void> main() async {
  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      FlutterError.onError = (details) {
        AppServices.logStore.error(
          'flutter',
          'FlutterError',
          error: details.exception,
          stackTrace: details.stack,
        );
        FlutterError.presentError(details);
      };

      AppServices.logStore.info('app', 'start');

      final prewarmSuccess = await AppServices.prewarm();
      if (!prewarmSuccess) {
        AppServices.logStore.warn('app', 'prewarm_failed_continuing_anyway');
      }

      ThemeMode initialThemeMode = ThemeMode.system;
      Locale initialLocale = const Locale('zh', 'CN');

      try {
        final themeModeStr = await AppServices.dataService.getThemeMode();
        final localeStr = await AppServices.dataService.getLocale();
        initialThemeMode = _parseThemeMode(themeModeStr);
        initialLocale = _parseLocale(localeStr);
      } catch (e) {
        AppServices.logStore.error('app', 'load_settings_failed', error: e);
      }

      runApp(
        BattleManApp(
          initialThemeMode: initialThemeMode,
          initialLocale: initialLocale,
        ),
      );
    },
    (error, stack) {
      AppServices.logStore.error(
        'zone',
        'uncaught',
        error: error,
        stackTrace: stack,
      );
      _showFatalError(error, stack);
    },
  );
}

void _showFatalError(Object error, StackTrace stack) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final context = appNavigatorKey.currentContext;
    if (context != null && context.mounted) {
      showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          backgroundColor: const Color(0xFFFFFFFF),
          title: const Text(
            '发生错误',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '应用程序遇到了一个错误：',
                  style: TextStyle(color: Color(0xFF8E8E93)),
                ),
                const SizedBox(height: 12),
                Text(
                  error.toString(),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: Color(0xFF2D2D2D),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text(
                '关闭',
                style: TextStyle(color: Color(0xFF2D2D2D)),
              ),
            ),
          ],
        ),
      );
    }
  });
}

ThemeMode _parseThemeMode(String value) {
  switch (value) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    default:
      return ThemeMode.system;
  }
}

String _themeModeToString(ThemeMode mode) {
  switch (mode) {
    case ThemeMode.light:
      return 'light';
    case ThemeMode.dark:
      return 'dark';
    default:
      return 'system';
  }
}

Locale _parseLocale(String value) {
  if (value.startsWith('en')) return const Locale('en', 'US');
  return const Locale('zh', 'CN');
}

String _localeToString(Locale locale) {
  return '${locale.languageCode}_${locale.countryCode ?? ''}';
}

class BattleManApp extends StatefulWidget {
  final ThemeMode initialThemeMode;
  final Locale initialLocale;

  const BattleManApp({
    super.key,
    this.initialThemeMode = ThemeMode.system,
    this.initialLocale = const Locale('zh', 'CN'),
  });

  static void setLocale(BuildContext context, Locale newLocale) {
    final state = context.findAncestorStateOfType<_BattleManAppState>();
    state?.setLocale(newLocale);
  }

  static void setThemeMode(BuildContext context, ThemeMode newThemeMode) {
    final state = context.findAncestorStateOfType<_BattleManAppState>();
    state?.setThemeMode(newThemeMode);
  }

  static ThemeMode getThemeMode(BuildContext context) {
    final state = context.findAncestorStateOfType<_BattleManAppState>();
    return state?._themeMode ?? ThemeMode.system;
  }

  @override
  State<BattleManApp> createState() => _BattleManAppState();
}

class _BattleManAppState extends State<BattleManApp> {
  late ThemeMode _themeMode;
  late Locale _locale;

  // 极简冷淡色系，去掉了强烈的品牌色
  static const Color _bgLight = Color(0xFFF7F7F6);
  static const Color _surfaceLight = Color(0xFFFFFFFF);
  static const Color _textPrimaryLight = Color(0xFF2D2D2D);

  static const Color _bgDark = Color(0xFF1C1C1E);
  static const Color _surfaceDark = Color(0xFF2C2C2E);
  static const Color _textPrimaryDark = Color(0xFFE5E5EA);

  @override
  void initState() {
    super.initState();
    _themeMode = widget.initialThemeMode;
    _locale = widget.initialLocale;
  }

  void setLocale(Locale newLocale) {
    if (_locale == newLocale) return;
    setState(() {
      _locale = newLocale;
    });
    _persistLocale(newLocale);
  }

  void setThemeMode(ThemeMode newThemeMode) {
    if (_themeMode == newThemeMode) return;
    setState(() {
      _themeMode = newThemeMode;
    });
    _persistThemeMode(newThemeMode);
  }

  Future<void> _persistThemeMode(ThemeMode mode) async {
    try {
      await AppServices.dataService.setThemeMode(_themeModeToString(mode));
    } catch (e) {
      AppServices.logStore.error('app', 'persist_theme_failed', error: e);
    }
  }

  Future<void> _persistLocale(Locale locale) async {
    try {
      await AppServices.dataService.setLocale(_localeToString(locale));
    } catch (e) {
      AppServices.logStore.error('app', 'persist_locale_failed', error: e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      scaffoldMessengerKey: appScaffoldMessengerKey,
      title: '时序智配',
      onGenerateTitle: (context) => AppStrings.of(context, 'app_title'),
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: _themeMode,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      locale: _locale,
      home: const MainScreen(),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final bgColor = isDark ? _bgDark : _bgLight;
    final surfaceColor = isDark ? _surfaceDark : _surfaceLight;
    final textColor = isDark ? _textPrimaryDark : _textPrimaryLight;
    final textSecondary = isDark
        ? const Color(0xFF8E8E93)
        : const Color(0xFF8E8E93);
    final indicatorColor = isDark
        ? const Color(0xFF3A3A3C)
        : const Color(0xFFF2F2F2);

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: bgColor,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF8E8E93), // 中性基础色
        brightness: brightness,
        surface: surfaceColor,
        onSurface: textColor,
        primary: textColor, // Primary 颜色即为主文本色，保持克制
      ),
      splashColor: Colors.transparent, // 移除点击水波纹
      highlightColor: Colors.transparent, // 移除点击高亮
    );

    final text = base.textTheme;

    return base.copyWith(
      textTheme: text.copyWith(
        headlineMedium: text.headlineMedium?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: textColor,
        ),
        titleLarge: text.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
          color: textColor,
        ),
        titleMedium: text.titleMedium?.copyWith(
          fontWeight: FontWeight.w500,
          letterSpacing: 0.2,
          color: textColor,
        ),
        bodyLarge: text.bodyLarge?.copyWith(
          height: 1.6, // 宽松的行距
          letterSpacing: 0.1,
          color: textColor,
        ),
        bodyMedium: text.bodyMedium?.copyWith(
          height: 1.6,
          color: textSecondary,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: textColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textColor,
          fontSize: 22,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0, // 0海拔，通过外部容器加微阴影
        color: surfaceColor,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 80,
        elevation: 0,
        backgroundColor: surfaceColor.withOpacity(0.9), // 半透明为毛玻璃做准备
        indicatorColor: indicatorColor,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? textColor : textSecondary,
            letterSpacing: 0.2,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData?>((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? textColor : textSecondary,
            size: 24,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: surfaceColor.withOpacity(0.9),
        useIndicator: true,
        indicatorColor: indicatorColor,
        selectedIconTheme: IconThemeData(color: textColor),
        unselectedIconTheme: IconThemeData(color: textSecondary),
        selectedLabelTextStyle: TextStyle(
          fontWeight: FontWeight.w600,
          color: textColor,
          fontSize: 12,
        ),
        unselectedLabelTextStyle: TextStyle(
          fontWeight: FontWeight.w400,
          color: textSecondary,
          fontSize: 12,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceColor,
        elevation: 0.0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24.0),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark
            ? const Color(0xFF48484A)
            : const Color(0xFF2D2D2D),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
