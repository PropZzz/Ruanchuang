import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_globals.dart';
import 'screens/main_screen.dart';
import 'ui/app_theme.dart';
import 'services/app_services.dart';
import 'theme/app_theme.dart';
import 'utils/app_strings.dart';
import 'utils/mobile_feedback.dart';

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
    if (context == null || !context.mounted) return;

    if (MobileFeedback.isMobilePhone(context)) {
      MobileFeedback.showInfo(
        context,
        zhMessage:
            '\u5f53\u524d\u64cd\u4f5c\u6682\u65f6\u65e0\u6cd5\u5b8c\u6210\uff0c\u5df2\u81ea\u52a8\u8bb0\u5f55\u5f02\u5e38\uff0c\u8bf7\u7a0d\u540e\u91cd\u8bd5\u3002',
        enMessage:
            'This action could not be completed. The error was logged, please try again later.',
      );
      return;
    }

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: const Color(0xFFFFFFFF),
        title: const Text(
          '\u64cd\u4f5c\u672a\u5b8c\u6210',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '\u5e94\u7528\u9047\u5230\u5f02\u5e38\uff0c\u5df2\u81ea\u52a8\u8bb0\u5f55\u3002\u8bf7\u8fd4\u56de\u540e\u91cd\u8bd5\uff1b\u5982\u679c\u95ee\u9898\u6301\u7eed\uff0c\u8bf7\u5230\u201c\u6211\u7684 > \u8bca\u65ad\u201d\u67e5\u770b\u65e5\u5fd7\u3002',
                style: TextStyle(color: Color(0xFF8E8E93)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text(
              '\u5173\u95ed',
              style: TextStyle(color: Color(0xFF2D2D2D)),
            ),
          ),
        ],
      ),
    );
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

  static void setAccentColor(BuildContext context, Color color) {
    final state = context.findAncestorStateOfType<_BattleManAppState>();
    state?.setAccentColor(color);
  }

  static Color getAccentColor(BuildContext context) {
    final state = context.findAncestorStateOfType<_BattleManAppState>();
    return state?._accentColor ?? AppThemeTokens.recoveryLight;
  }

  @override
  State<BattleManApp> createState() => _BattleManAppState();
}

class _BattleManAppState extends State<BattleManApp> {
  late ThemeMode _themeMode;
  late Locale _locale;
<<<<<<< HEAD
  Color _accentColor = AppThemeTokens.recoveryLight;
=======
>>>>>>> d9a13f017b1d6e2337be5f4fe471d93a1f14c33d

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

  void setAccentColor(Color color) {
    if (_accentColor == color) return;
    setState(() {
      _accentColor = color;
    });
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
      title: '\u65f6\u5e8f\u667a\u914d',
      onGenerateTitle: (context) => AppStrings.of(context, 'app_title'),
<<<<<<< HEAD
      theme: AppTheme.build(Brightness.light, accentColor: _accentColor),
      darkTheme: AppTheme.build(Brightness.dark, accentColor: _accentColor),
=======
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
>>>>>>> d9a13f017b1d6e2337be5f4fe471d93a1f14c33d
      themeMode: _themeMode,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      locale: _locale,
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        final width = mediaQuery.size.width;
        final currentScale = mediaQuery.textScaler.scale(1);
        final maxScale = width < 420 ? 1.08 : 1.16;
        final clampedScale = currentScale.clamp(0.95, maxScale);

        return MediaQuery(
          data: mediaQuery.copyWith(
            textScaler: TextScaler.linear(clampedScale),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const MainScreen(),
    );
  }
}
