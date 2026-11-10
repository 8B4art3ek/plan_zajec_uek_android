import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plan_zajec_uek/domain/entities/schedule_entry.dart';
import 'package:plan_zajec_uek/presentation/widgets/class_card.dart';
import 'package:plan_zajec_uek/presentation/widgets/schedule_entry_details_sheet.dart';

void main() {
  for (final scale in [1.0, 2.0]) {
    for (final moved in [false, true]) {
      testWidgets(
          'group is visible and fits a small card at scale $scale moved=$moved',
          (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final entry = ScheduleEntry(
            id: '1',
            subject: 'Matematyka',
            classType: 'wykład',
            lecturer: 'Prowadzący',
            room: 'Sala A',
            date: DateTime(2026, 11, 3),
            startTime: '09:00',
            endTime: '10:30',
            weekday: '',
            durationHours: 2,
            groupId: 'lecturer:123',
            groupType: GroupType.dean,
            studentGroups: 'ZIISS1-2311AD, ZIISS1-2311IO',
            isMoved: moved);
        await tester.pumpWidget(MaterialApp(
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!),
            home: Scaffold(
                body: Builder(
                    builder: (context) => ListView(children: [
                          ClassCard(
                              entry: entry,
                              onTap: () => showScheduleEntryDetailsSheet(
                                  context: context, entry: entry)),
                        ])))));
        await tester.pumpAndSettle();
        expect(find.text(entry.studentGroups), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byType(ClassCard));
        await tester.pumpAndSettle();
        expect(find.text('Grupa'), findsOneWidget);
        expect(find.text(entry.studentGroups), findsWidgets);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
