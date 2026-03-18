import 'package:flutter/material.dart';

import '../../app_globals.dart';
import 'reminder_notifier_base.dart';

class IoReminderNotifier implements ReminderNotifier {
  @override
  Future<void> showReminder({
    required String title,
    required String body,
    List<ReminderAction> actions = const [],
  }) async {
    final messenger = appScaffoldMessengerKey.currentState;
    if (messenger == null) {
      debugPrint('[reminder] $title | $body');
      return;
    }

    messenger.showSnackBar(
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

ReminderNotifier createReminderNotifier() => IoReminderNotifier();

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

