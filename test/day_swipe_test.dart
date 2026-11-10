import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plan_zajec_uek/domain/entities/schedule_entry.dart';
import 'package:plan_zajec_uek/presentation/providers/providers.dart';
import 'package:plan_zajec_uek/presentation/screens/home/home_screen.dart';
import 'package:plan_zajec_uek/presentation/widgets/class_card.dart';

class _Colors extends ClassTypeColorsNotifier {
  @override
  Future<Map<String, Color>> build() async => {};
}

Future<ProviderContainer> _pump(WidgetTester tester,
    {bool withClasses = false,
    RefreshInfo? refreshInfo,
    bool loading = false,
    bool error = false}) async {
  final pending = Completer<List<ScheduleEntry>>();
  final container = ProviderContainer(overrides: [
    selectedDateProvider.overrideWith((ref) => DateTime(2026, 10, 25)),
    classTypeColorsProvider.overrideWith(_Colors.new),
    refreshInfoProvider.overrideWith((ref) async =>
        refreshInfo ??
        const RefreshInfo(lastRefreshAt: null, status: null, error: null)),
    todayScheduleProvider.overrideWith((ref) async {
      if (loading) return pending.future;
      if (error) throw StateError('Offline');
      return withClasses
          ? List.generate(
              12,
              (i) => ScheduleEntry(
                    id: '$i',
                    subject: 'Przedmiot $i',
                    classType: 'Wykład',
                    lecturer: 'Prowadzący',
                    room: 'Sala 10',
                    date: DateTime(2026, 10, 25),
                    startTime: '${(8 + i).toString().padLeft(2, '0')}:00',
                    endTime: '${(9 + i).toString().padLeft(2, '0')}:00',
                    weekday: 'niedziela',
                    durationHours: 1,
                    groupId: '1',
                    groupType: GroupType.dean,
                  ))
          : [];
    }),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
      container: container, child: MaterialApp(home: HomeScreen())));
  if (loading) {
    await tester.pump();
  } else {
    await tester.pumpAndSettle();
  }
  return container;
}

void main() {
  testWidgets('offline notice keeps saved classes visible without raw errors',
      (tester) async {
    await _pump(tester,
        withClasses: true,
        refreshInfo: RefreshInfo(
            lastRefreshAt: DateTime(2026, 10, 21, 10, 30),
            status: 'partial_error',
            error: 'Exception: HTTP 500',
            nextRetryAt: DateTime(2026, 10, 22, 11, 15)));
    expect(find.textContaining('Nie udało się odświeżyć planu z serwera UEK'),
        findsOneWidget);
    expect(find.textContaining('21.10.2026 10:30'), findsWidgets);
    expect(find.textContaining('11:15'), findsOneWidget);
    expect(find.textContaining('HTTP 500'), findsNothing);
    expect(find.byType(ClassCard), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('first-download failure explains missing saved plan',
      (tester) async {
    await _pump(tester,
        refreshInfo: const RefreshInfo(
            lastRefreshAt: null, status: 'partial_error', error: 'HTTP 500'));
    expect(find.textContaining('Jeśli plan nie był wcześniej pobrany'),
        findsOneWidget);
  });

  testWidgets('weekday is beside date in a single-line label', (tester) async {
    await _pump(tester);
    final tooltip = find.byTooltip('25.10.2026 · niedziela');
    expect(tooltip, findsOneWidget);
    final label = tester.widget<Text>(
        find.descendant(of: tooltip, matching: find.byType(Text)).first);
    expect(label.data, '25.10.2026 · niedziela');
    expect(label.data, isNot(contains('\n')));
    expect(label.maxLines, 1);
  });

  testWidgets('left and right swipes move one calendar day across DST',
      (tester) async {
    final container = await _pump(tester);
    final body = find.byType(ListView);
    await tester.drag(body, const Offset(-250, 0));
    await tester.pumpAndSettle();
    expect(container.read(selectedDateProvider), DateTime(2026, 10, 26));
    await tester.drag(body, const Offset(250, 0));
    await tester.pumpAndSettle();
    expect(container.read(selectedDateProvider), DateTime(2026, 10, 25));
    await tester.drag(body, const Offset(250, 0));
    await tester.pumpAndSettle();
    expect(container.read(selectedDateProvider), DateTime(2026, 10, 24));
  });

  testWidgets('vertical scroll and tiny horizontal drags do not change day',
      (tester) async {
    final container = await _pump(tester, withClasses: true);
    final position =
        tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(0));
    expect(container.read(selectedDateProvider), DateTime(2026, 10, 25));
    await tester.drag(find.byType(ListView), const Offset(-35, 0));
    await tester.pumpAndSettle();
    expect(container.read(selectedDateProvider), DateTime(2026, 10, 25));
  });

  testWidgets(
      'swipe over a class changes day without opening details and resets scroll',
      (tester) async {
    final container = await _pump(tester, withClasses: true);
    await tester.drag(find.byType(ListView), const Offset(0, -250));
    await tester.pumpAndSettle();
    await tester.drag(
        find.byType(ClassCard).hitTestable().first, const Offset(-240, 0));
    await tester.pumpAndSettle();
    expect(container.read(selectedDateProvider), DateTime(2026, 10, 26));
    expect(find.text('Typ zajęć'), findsNothing);
    final position =
        tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    expect(position.pixels, 0);
    await tester.tap(find.byType(ClassCard).first);
    await tester.pumpAndSettle();
    expect(find.text('Typ zajęć'), findsOneWidget);
  });

  for (final mode in ['loading', 'error']) {
    testWidgets('swipe works while $mode', (tester) async {
      final container = await _pump(tester,
          loading: mode == 'loading', error: mode == 'error');
      await tester.drag(find.byType(ListView), const Offset(-240, 0));
      await tester.pump();
      expect(container.read(selectedDateProvider), DateTime(2026, 10, 26));
    });
  }
}
