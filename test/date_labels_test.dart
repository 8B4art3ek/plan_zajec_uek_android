import 'package:flutter_test/flutter_test.dart';
import 'package:plan_zajec_uek/core/date_labels.dart';

void main() {
  test('weekdays come from the date, including Sunday and time change', () {
    expect(polishWeekday(DateTime(2026, 9, 27)), 'niedziela');
    expect(polishWeekday(DateTime(2026, 10, 25)), 'niedziela');
    expect(polishWeekday(DateTime(2026, 10, 26)), 'poniedziałek');
    expect(polishWeekday(DateTime(2026, 11, 5)), 'czwartek');
  });
}
