class ReminderAction {
  final String label;
  final void Function() onPressed;

  const ReminderAction({
    required this.label,
    required this.onPressed,
  });
}

abstract class ReminderNotifier {
  Future<void> showReminder({
    required String title,
    required String body,
    List<ReminderAction> actions = const [],
  });
}

