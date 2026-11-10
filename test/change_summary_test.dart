import 'package:flutter_test/flutter_test.dart';
import 'package:plan_zajec_uek/domain/entities/schedule_change.dart';
import 'package:plan_zajec_uek/domain/entities/change_summary.dart';
import 'package:plan_zajec_uek/domain/entities/schedule_notification.dart';

ScheduleChange _change(String description) => ScheduleChange(
    groupId: '1',
    subject: 'Matematyka',
    description: description,
    detectedAt: DateTime(2026, 11, 3));
void main() {
  test('legacy pending move and destination become one changed event', () {
    final marker = _change(
        'Dodano zajęcia\nMatematyka · 02.11.2026 · 08:00–09:30 · Przeniesienie zajęć · Jan · Przeniesione: 03.11.2026 ');
    final target = _change(
        'Dodano zajęcia\nMatematyka · 03.11.2026 · 18:30–20:00 · wykład · Sala A · Jan');
    final merged = ChangeSummary.coalesceMoves([marker, target]);
    expect(merged, hasLength(1));
    final summary = ChangeSummary.from(merged.single);
    expect(summary.kind, ChangeKind.updated);
    expect(summary.before, contains('02.11.2026'));
    expect(summary.after, contains('03.11.2026'));
    expect(ChangeSummary.from(marker).kind, ChangeKind.updated);
    final notification = ScheduleNotification.fromChanges([marker, target])!;
    expect(notification.title, 'Zmieniono zajęcia: Matematyka');
    expect(ChangeSummary.coalesceMoves([target, marker]), hasLength(1));
    expect([marker, target], hasLength(2));
  });
  test(
      'room-only change highlights only differing rooms and keeps date as context',
      () {
    final value = ChangeSummary.from(_change('Zmieniono zajęcia\n'
        'Przed: Matematyka · 04.11.2026 · 09:00–10:30 · wykład · Sala A · Prowadzący\n'
        'Teraz: Matematyka · 04.11.2026 · 09:00–10:30 · wykład · Sala B · Prowadzący'));
    expect(value.before, 'Sala A');
    expect(value.after, 'Sala B');
    expect(value.context, '04.11.2026 · 09:00–10:30');
    expect(value.kind, ChangeKind.updated);
  });
  test('added and removed entries have distinct action labels', () {
    expect(ChangeSummary.from(_change('Dodano zajęcia\nSala A')).kind,
        ChangeKind.added);
    expect(ChangeSummary.from(_change('Usunięto z planu\nSala A')).kind,
        ChangeKind.removed);
    final notification = ScheduleNotification.fromChanges([
      _change('Dodano zajęcia\nSala A'),
      _change('Usunięto z planu\nSala B')
    ])!;
    expect(notification.body, 'Dodano: 1 · Usunięto: 1');
  });
}
