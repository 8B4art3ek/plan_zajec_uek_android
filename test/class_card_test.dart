import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plan_zajec_uek/core/theme/app_theme.dart';
import 'package:plan_zajec_uek/domain/entities/schedule_entry.dart';
import 'package:plan_zajec_uek/presentation/widgets/class_card.dart';

ScheduleEntry _entry(String id, String start, String end,
        {bool moved = false}) =>
    ScheduleEntry(
      id: id,
      subject: 'Instrumentarium przetwarzania danych',
      classType: 'Ćwiczenia e-learningowe',
      lecturer: 'Prowadzący z długim nazwiskiem',
      room: 'Biblioteka, sala 425',
      date: DateTime(2026, 10, 17),
      startTime: start,
      endTime: end,
      weekday: 'sobota',
      durationHours: 2,
      groupId: '1',
      groupType: GroupType.dean,
      isMoved: moved,
      newDate: moved ? DateTime(2026, 11, 20) : null,
      newStartTime: moved ? '16:45' : null,
      newEndTime: moved ? '18:15' : null,
    );

void main() {
  for (final scale in [1.0, 1.5, 2.0]) {
    testWidgets('full and half cards fit at text scale $scale', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.themeFor(AppThemeKind.midnight),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Scaffold(
              body: ListView(
                  children: buildScheduleWidgets([
            _entry('1', '09:00', '10:30'),
            _entry('2', '10:45', '12:15'),
            _entry('3', '10:45', '12:15', moved: true),
          ]))),
        ),
      ));
      expect(tester.takeException(), isNull);
      final cards = find.byType(ClassCard);
      expect(cards, findsNWidgets(3));
      expect(tester.getSize(cards.at(1)).height,
          tester.getSize(cards.at(2)).height);
    });
  }

  test('break starts at the last actual class, ignoring moved entries', () {
    final widgets = buildScheduleWidgets([
      _entry('1', '08:00', '09:30'),
      _entry('2', '09:45', '11:15', moved: true),
      _entry('3', '15:00', '16:30'),
    ]);
    expect(widgets.whereType<BreakBlock>().single.minutes, 330);
  });

  test('overlapping long class prevents a false break', () {
    final widgets = buildScheduleWidgets([
      _entry('1', '09:00', '13:00'),
      _entry('2', '10:00', '11:00'),
      _entry('3', '12:00', '13:00'),
    ]);
    expect(widgets.whereType<BreakBlock>(), isEmpty);
  });

  test('does not show fifteen-minute breaks', () {
    final widgets = buildScheduleWidgets([
      _entry('1', '09:00', '10:30'),
      _entry('2', '10:45', '12:15'),
    ]);
    expect(widgets.whereType<BreakBlock>(), isEmpty);
  });
}
