// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:html' as html;

import 'package:flutter/material.dart';

import '../../app_globals.dart';
import 'reminder_notifier_base.dart';

class WebReminderNotifier implements ReminderNotifier {
  @override
  Future<void> showReminder({
    required String title,
    required String body,
    List<ReminderAction> actions = const [],
  }) async {
    // Best effort: browser notification (permission-gated). If we have actions,
    // we always show an in-app snackbar so users can interact (snooze).
    if (actions.isEmpty) {
      try {
        final perm = html.Notification.permission;
        if (perm != 'granted') {
          final p = await html.Notification.requestPermission();
          if (p == 'granted') {
            html.Notification(title, body: body);
            return;
          }
        } else {
          html.Notification(title, body: body);
          return;
        }
      } catch (_) {
        // Ignore and fallback.
      }
    }

    final messenger = appScaffoldMessengerKey.currentState;
    messenger?.showSnackBar(
      SnackBar(
        content: _ReminderSnackContent(
          title: title,
          body: body,
          actions: actions,
        ),
        duration: const Duration(seconds: 12),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

ReminderNotifier createReminderNotifier() => WebReminderNotifier();

class _ReminderSnackContent extends StatelessWidget {
  const _ReminderSnackContent({
    required this.title,
    required this.body,
    required this.actions,
  });

  final String title;
  final String body;
  final List<ReminderAction> actions;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title),
        const SizedBox(height: 2),
        Text(body),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 0,
            children: actions
                .map(
                  (a) => TextButton(
                    onPressed: () {
                      appScaffoldMessengerKey.currentState?.hideCurrentSnackBar();
                      a.onPressed();
                    },
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    child: Text(a.label),
                  ),
                )
                .toList(),
          ),
        ],
      ],
    );
  }
}

