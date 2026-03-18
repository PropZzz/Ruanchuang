import 'package:flutter/material.dart';

/// App-wide navigation and snackbar keys.
///
/// Keeps service-layer features (reminders, imports) decoupled from page contexts.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> appScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();
