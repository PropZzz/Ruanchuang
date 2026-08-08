import 'package:flutter_test/flutter_test.dart';
import 'package:shixuzhipei/services/scheduling/urgent_deadline.dart';

void main() {
  test('today default preserves a two-hour rollover past midnight', () {
    final deadline = defaultUrgentDeadline(
      now: DateTime(2026, 8, 6, 23, 30),
      scheduleDay: DateTime(2026, 8, 6),
    );

    expect(deadline, DateTime(2026, 8, 7, 1, 30));
  });

  test('future schedule day defaults to 17:00 on that day', () {
    final deadline = defaultUrgentDeadline(
      now: DateTime(2026, 8, 6, 9),
      scheduleDay: DateTime(2026, 8, 8, 11),
    );

    expect(deadline, DateTime(2026, 8, 8, 17));
  });

  test('rejects a deadline that is not after now', () {
    expect(
      isUrgentDeadlineValid(
        now: DateTime(2026, 8, 6, 12),
        scheduleDay: DateTime(2026, 8, 6),
        deadline: DateTime(2026, 8, 6, 12),
      ),
      isFalse,
    );
  });

  test('rejects a past schedule day even when the deadline is future', () {
    expect(
      isUrgentDeadlineValid(
        now: DateTime(2026, 8, 6, 12),
        scheduleDay: DateTime(2026, 8, 5),
        deadline: DateTime(2026, 8, 6, 13),
      ),
      isFalse,
    );
  });

  test('date picker upper bound is five years after its first date', () {
    expect(
      urgentDeadlinePickerLastDate(firstDate: DateTime(2035, 7, 12)),
      DateTime(2040, 7, 12),
    );
  });
}
