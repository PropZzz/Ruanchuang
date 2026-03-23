import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/app_services.dart';

class MobileFeedback {
  static bool isMobilePhone(BuildContext context) {
    if (kIsWeb) return false;

    final platform = defaultTargetPlatform;
    final isMobilePlatform =
        platform == TargetPlatform.android || platform == TargetPlatform.iOS;
    if (!isMobilePlatform) return false;

    final width = MediaQuery.maybeSizeOf(context)?.width ?? 0;
    return width > 0 && width < 700;
  }

  static bool isNarrow(BuildContext context, {double breakpoint = 700}) {
    final width = MediaQuery.maybeSizeOf(context)?.width ?? breakpoint;
    return width < breakpoint;
  }

  static String localized(
    BuildContext context, {
    required String zh,
    required String en,
  }) {
    final locale = Localizations.maybeLocaleOf(context);
    if (locale?.languageCode.toLowerCase().startsWith('zh') ?? false) {
      return zh;
    }
    return en;
  }

  static BoxConstraints dialogConstraints(
    BuildContext context, {
    double maxWidth = 560,
  }) {
    final width = MediaQuery.maybeSizeOf(context)?.width ?? maxWidth;
    final resolved = math.max(280.0, math.min(maxWidth, width - 32));
    return BoxConstraints(maxWidth: resolved);
  }

  static void showInfo(
    BuildContext context, {
    required String zhMessage,
    required String enMessage,
  }) {
    _showSnackBar(
      context,
      localized(context, zh: zhMessage, en: enMessage),
    );
  }

  static void showError(
    BuildContext context, {
    required String category,
    required String message,
    required String zhMessage,
    required String enMessage,
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> data = const {},
    bool silentOnPhone = false,
  }) {
    AppServices.logStore.error(
      category,
      message,
      error: error,
      stackTrace: stackTrace,
      data: data,
    );

    if (silentOnPhone && isMobilePhone(context)) return;

    _showSnackBar(
      context,
      localized(context, zh: zhMessage, en: enMessage),
    );
  }

  static void _showSnackBar(BuildContext context, String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
