import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_globals.dart';
import 'screens/main_screen.dart';
import 'services/app_services.dart';
import 'utils/app_strings.dart';

Future<void> main() async {
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

  await runZonedGuarded(() async {
    AppServices.logStore.info('app', 'start');
    await AppServices.prewarm();
    runApp(const BattleManApp());
  }, (error, stack) {
    AppServices.logStore.error(
      'zone',
      'uncaught',
      error: error,
      stackTrace: stack,
    );
  });
}

class BattleManApp extends StatefulWidget {
  const BattleManApp({super.key});

  static void setLocale(BuildContext context, Locale newLocale) {
    final state = context.findAncestorStateOfType<_BattleManAppState>();
    state?.setLocale(newLocale);
  }

  @override
  State<BattleManApp> createState() => _BattleManAppState();
}

class _BattleManAppState extends State<BattleManApp> {
  Locale _locale = const Locale('zh', 'CN');

  void setLocale(Locale newLocale) {
    setState(() {
      _locale = newLocale;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      scaffoldMessengerKey: appScaffoldMessengerKey,
      // Keep a stable ASCII fallback; use onGenerateTitle for localized title.
      title: 'BattleMan',
      onGenerateTitle: (context) => AppStrings.of(context, 'app_title'),
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00BFA5),
          secondary: const Color(0xFF2979FF),
          tertiary: const Color(0xFFFF9100),
        ),
      ),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('zh', 'CN'),
        Locale('en', 'US'),
      ],
      locale: _locale,
      home: const MainScreen(),
    );
  }
}
