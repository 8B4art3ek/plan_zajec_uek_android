import 'package:flutter_test/flutter_test.dart';
import 'package:plan_zajec_uek/domain/entities/schedule_change.dart';
import 'package:plan_zajec_uek/domain/entities/schedule_entry.dart';

final now = DateTime(2026, 10, 20, 22);
final entry = ScheduleEntry(
    id: '1',
    subject: 'Matematyka',
    classType: 'CW',
    lecturer: 'Jan',
    room: 'A',
    date: DateTime(2026, 10, 20),
    startTime: '09:00',
    endTime: '10:30',
    weekday: '',
    durationHours: 2,
    groupId: '1',
    groupType: GroupType.dean);

void main() {
  test('pairs original move marker and destination into one changed lesson',
      () {
    final moved = entry.copyWith(
        id: 'marker',
        isMoved: true,
        classType: 'Przeniesienie zajęć',
        originalDate: entry.date,
        originalStartTime: entry.startTime,
        newDate: DateTime(2026, 10, 21));
    final target = entry.copyWith(
        id: 'target',
        date: DateTime(2026, 10, 21),
        startTime: '18:30',
        endTime: '20:00',
        room: 'B');
    final changes = ScheduleChange.compare([entry], [moved, target], now);
    expect(changes, hasLength(1));
    expect(changes.single.description, startsWith('Zmieniono zajęcia'));
    expect(changes.single.description, contains('20.10.2026'));
    expect(changes.single.description, contains('21.10.2026'));
    expect(changes.single.description, contains('18:30–20:00'));
    expect(
        ScheduleChange.compare([moved, target], [moved, target], now), isEmpty);
    expect(ScheduleChange.compare([entry], [target, moved], now), hasLength(1));
  });
  test('a newly discovered move is changed, not added, even without an old row',
      () {
    final moved = entry.copyWith(
        id: 'marker',
        isMoved: true,
        newDate: DateTime(2026, 10, 21),
        newStartTime: '12:00');
    final target = entry.copyWith(
        id: 'target', date: DateTime(2026, 10, 21), startTime: '12:00');
    final changes = ScheduleChange.compare([], [moved, target], now);
    expect(changes, hasLength(1));
    expect(changes.single.description, startsWith('Zmieniono zajęcia'));
  });
  test('same subject in another group or ambiguous destination is not consumed',
      () {
    final moved = entry.copyWith(
        id: 'marker', isMoved: true, newDate: DateTime(2026, 10, 21));
    final target = entry.copyWith(id: 'target', date: DateTime(2026, 10, 21));
    final other = target.copyWith(id: 'other', groupId: '2');
    final changes =
        ScheduleChange.compare([entry], [moved, target, other], now);
    expect(changes, hasLength(2));
    expect(
        changes
            .where((change) => change.description.startsWith('Dodano'))
            .single
            .groupId,
        '2');
    final second = target.copyWith(id: 'second', startTime: '16:00');
    final ambiguous =
        ScheduleChange.compare([entry], [moved, target, second], now);
    expect(ambiguous.where((change) => change.description.startsWith('Dodano')),
        hasLength(2));
  });
  test('later changes to a moved destination are reported once', () {
    final moved = entry.copyWith(
        id: 'marker', isMoved: true, newDate: DateTime(2026, 10, 21));
    final target = entry.copyWith(id: 'target', date: DateTime(2026, 10, 21));
    final result = ScheduleChange.compare(
        [moved, target], [moved, target.copyWith(room: 'B')], now);
    expect(result, hasLength(1));
    expect(result.single.description, startsWith('Zmieniono zajęcia'));
    expect(result.single.description, contains(' · B · '));
  });
  test(
      'a moved class with a past original date still reports its upcoming target',
      () {
    final past = entry.copyWith(date: DateTime(2026, 10, 19));
    final moved = past.copyWith(
        isMoved: true, newDate: DateTime(2026, 10, 21), newStartTime: '12:00');
    expect(ScheduleChange.compare([past], [moved], now), hasLength(1));
  });
  test(
      'captures room, teacher, subject and move status changes with before/after details',
      () {
    final changed = entry.copyWith(
        room: 'B',
        lecturer: 'Anna',
        subject: 'Analiza',
        isMoved: true,
        newDate: DateTime(2026, 10, 21),
        newStartTime: '11:00');
    final result = ScheduleChange.compare([entry], [changed], now);
    expect(result, hasLength(1));
    expect(result.single.description, contains('Przed:'));
    expect(result.single.description, contains('Teraz:'));
    expect(
        result.single.description, contains('Przeniesione: 21.10.2026 11:00'));
  });
  test('matches a uniquely rescheduled time even when its generated ID changes',
      () {
    final result = ScheduleChange.compare(
        [entry], [entry.copyWith(id: '2', startTime: '12:00')], now);
    expect(result, hasLength(1));
    expect(result.single.description, contains('Zmieniono zajęcia'));
  });
  test(
      'reports additions/removals but ignores past-day churn and unchanged data',
      () {
    expect(ScheduleChange.compare([entry], [entry], now), isEmpty);
    expect(ScheduleChange.compare([], [entry], now).single.description,
        contains('Dodano'));
    expect(ScheduleChange.compare([entry], [], now).single.description,
        contains('Usunięto'));
    final past = entry.copyWith(date: DateTime(2026, 10, 19));
    expect(ScheduleChange.compare([past], [], now), isEmpty);
  });
}
