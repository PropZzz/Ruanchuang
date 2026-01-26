import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'screens/main_screen.dart';

void main() {
  runApp(const BattleManApp());
}

class BattleManApp extends StatefulWidget {
  const BattleManApp({super.key});

  static void setLocale(BuildContext context, Locale newLocale) {
    _BattleManAppState? state = context.findAncestorStateOfType<_BattleManAppState>();
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
      title: '时序智配 BattleMan',
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
