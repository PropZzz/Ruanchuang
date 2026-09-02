import 'package:flutter_test/flutter_test.dart';
import 'package:shixuzhipei/screens/focus_page.dart';

void main() {
  test('completed minutes are calculated before the timer is reset', () {
    expect(
      completedMinutesForTimer(plannedMinutes: 60, remainingSeconds: 30 * 60),
      30,
    );
    expect(
      completedMinutesForTimer(plannedMinutes: 60, remainingSeconds: 0),
      60,
    );
    expect(
      completedMinutesForTimer(plannedMinutes: 60, remainingSeconds: 90 * 60),
      1,
    );
  });
}
