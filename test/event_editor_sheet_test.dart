import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plan_zajec_uek/domain/entities/schedule_entry.dart';
import 'package:plan_zajec_uek/domain/entities/user_event.dart';
import 'package:plan_zajec_uek/presentation/providers/providers.dart';
import 'package:plan_zajec_uek/presentation/widgets/event_editor_sheet.dart';

class _Events extends UserEventsNotifier {
  final result = Completer<List<UserEvent>>();
  UserEvent? saved;
  @override
  Future<List<UserEvent>> build() => result.future;
  @override
  Future<void> updateUserEvent(UserEvent event) async {
    saved = event;
  }
}

void main() {
  testWidgets('editing waits for stored event and preserves its description',
      (tester) async {
    final events = _Events();
    final date = DateTime(2026, 10, 17);
    final entry = ScheduleEntry(
        id: 'event_1',
        subject: 'Egzamin',
        classType: 'Egzamin',
        lecturer: '',
        room: '',
        date: date,
        startTime: '09:00',
        endTime: '10:30',
        weekday: '',
        durationHours: 0,
        groupId: 'user',
        groupType: GroupType.dean);
    await tester.pumpWidget(ProviderScope(
      overrides: [userEventsProvider.overrideWith(() => events)],
      child: MaterialApp(
          home: Consumer(
              builder: (context, ref, _) => Scaffold(
                    body: TextButton(
                        onPressed: () => showUserEventSheetForEntry(
                            context: context, ref: ref, entry: entry),
                        child: const Text('Edytuj')),
                  ))),
    ));
    await tester.tap(find.text('Edytuj'));
    await tester.pumpAndSettle();
    expect(find.byType(UserEventSheet), findsNothing);
    events.result.complete([
      UserEvent(
          id: 1,
          title: 'Egzamin',
          eventType: 'Egzamin',
          description: 'Ważna notatka',
          date: date,
          startTime: '09:00',
          endTime: '10:30')
    ]);
    await tester.pumpAndSettle();
    expect(find.byType(UserEventSheet), findsOneWidget);
    await tester.tap(find.text('Zapisz zmiany'));
    await tester.pumpAndSettle();
    expect(events.saved?.description, 'Ważna notatka');
  });
}
