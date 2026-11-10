import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plan_zajec_uek/data/datasources/transit_service.dart';
import 'package:plan_zajec_uek/domain/entities/transit_journey.dart';
import 'package:plan_zajec_uek/presentation/providers/transit_provider.dart';
import 'package:plan_zajec_uek/presentation/widgets/transit_place_field.dart';

class _Places extends TransitService {
  final queries = <String>[];
  Future<List<TransitPlace>> Function(String)? handler;
  @override
  Future<List<TransitPlace>> searchPlaces(String query) async {
    queries.add(query);
    return handler != null
        ? await handler!(query)
        : [TransitPlace('$query wynik', 50.06, 19.95, description: 'Kraków')];
  }
}

void main() {
  late _Places service;
  late ValueNotifier<TransitPlace?> selected;
  final selections = <TransitPlace?>[];
  setUp(() {
    service = _Places();
    selected = ValueNotifier(null);
    selections.clear();
  });
  tearDown(() {
    service.close();
    selected.dispose();
  });
  Future<void> mount(WidgetTester tester, {double keyboard = 0}) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(ProviderScope(
      overrides: [transitServiceProvider.overrideWithValue(service)],
      child: MaterialApp(
          home: Scaffold(
        appBar: AppBar(title: const Text('Dojazdy')),
        body: Padding(
            padding: const EdgeInsets.all(16),
            child: ValueListenableBuilder(
              valueListenable: selected,
              builder: (_, value, __) => Column(children: [
                TransitPlaceField(
                    label: 'Skąd',
                    icon: Icons.trip_origin,
                    value: value,
                    onChanged: (place) {
                      selections.add(place);
                      selected.value = place;
                    }),
              ]),
            )),
      )),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('suggestions start at three characters after a debounced pause',
      (tester) async {
    await mount(tester);
    await tester.enterText(find.byType(TextField), 'Ru');
    await tester.pump(const Duration(seconds: 1));
    expect(service.queries, isEmpty);
    await tester.enterText(find.byType(TextField), 'Ruc');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(find.byType(TextField), 'Ruczaj');
    await tester.pump(const Duration(milliseconds: 449));
    expect(service.queries, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();
    expect(service.queries, ['Ruczaj']);
    expect(find.text('Ruczaj wynik'), findsOneWidget);
    await tester.tap(find.text('Ruczaj wynik'));
    await tester.pumpAndSettle();
    expect(selected.value!.name, 'Ruczaj wynik');
    await tester.pump(const Duration(seconds: 1));
    expect(service.queries, ['Ruczaj']);
  });

  testWidgets('late responses cannot replace newer matches', (tester) async {
    final old = Completer<List<TransitPlace>>();
    service.handler = (query) async => query == 'Ruczaj'
        ? await old.future
        : [const TransitPlace('Bochnia stacja', 49.97, 20.43)];
    await mount(tester);
    await tester.enterText(find.byType(TextField), 'Ruczaj');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.enterText(find.byType(TextField), 'Bochnia');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect(find.text('Bochnia stacja'), findsOneWidget);
    old.complete([const TransitPlace('Stary wynik', 50.06, 19.95)]);
    await tester.pumpAndSettle();
    expect(find.text('Stary wynik'), findsNothing);
    expect(find.text('Bochnia stacja'), findsOneWidget);
  });

  testWidgets(
      'typing hides stale options and Enter cannot select an old result',
      (tester) async {
    await mount(tester);
    await tester.enterText(find.byType(TextField), 'Ruczaj');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect(find.text('Ruczaj wynik'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Bochnia');
    await tester.pump();
    expect(find.text('Ruczaj wynik'), findsNothing);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(selected.value, isNull);
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(find.text('Bochnia wynik'), findsOneWidget);
  });

  testWidgets('editing an accepted place invalidates coordinates immediately',
      (tester) async {
    selected.value = const TransitPlace('Kampus UEK', 50.06, 19.95);
    await mount(tester);
    await tester.enterText(find.byType(TextField), 'Kampus U');
    expect(selected.value, isNull);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Kampus U');
    await tester.tap(find.byTooltip('Wyczyść skąd'));
    await tester.pump(const Duration(seconds: 1));
    expect(service.queries, isEmpty);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
  });

  testWidgets('moving the caret does not repeat geocoding', (tester) async {
    await mount(tester);
    await tester.enterText(find.byType(TextField), 'Ruczaj');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    tester.widget<TextField>(find.byType(TextField)).controller!.selection =
        const TextSelection.collapsed(offset: 1);
    await tester.pump(const Duration(seconds: 1));
    expect(service.queries, ['Ruczaj']);
  });

  testWidgets('errors can be retried without changing the query',
      (tester) async {
    var fail = true;
    service.handler = (query) async {
      if (fail) throw const TransitException('Chwilowy problem z połączeniem.');
      return [const TransitPlace('Ruczaj przystanek', 50.06, 19.95)];
    };
    await mount(tester);
    await tester.enterText(find.byType(TextField), 'Ruczaj');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect(find.text('Chwilowy problem z połączeniem.'), findsOneWidget);
    fail = false;
    await tester.tap(find.byTooltip('Ponów wyszukiwanie'));
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect(find.text('Ruczaj przystanek'), findsOneWidget);
    expect(service.queries, ['Ruczaj', 'Ruczaj']);
  });

  testWidgets('empty results are distinguished from network errors',
      (tester) async {
    service.handler = (_) async => [];
    await mount(tester);
    await tester.enterText(find.byType(TextField), 'Nieznane miejsce');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect(find.text('Brak pasujących miejsc. Dodaj nazwę miejscowości.'),
        findsOneWidget);
    expect(find.byTooltip('Ponów wyszukiwanie'), findsNothing);
  });

  testWidgets('suggestion list fits above the on-screen keyboard',
      (tester) async {
    service.handler = (_) async => [
          for (var i = 0; i < 8; i++)
            TransitPlace('Przystanek $i', 50.06, 19.95, description: 'Kraków')
        ];
    await mount(tester, keyboard: 240);
    await tester.enterText(find.byType(TextField), 'Kraków');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect(find.text('Przystanek 0'), findsOneWidget);
    expect(tester.getBottomRight(find.text('Przystanek 0')).dy, lessThan(400));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'disposing cancels the debounce and safely ignores an in-flight request',
      (tester) async {
    await mount(tester);
    await tester.enterText(find.byType(TextField), 'Ruczaj');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    expect(service.queries, isEmpty);
    final pending = Completer<List<TransitPlace>>();
    service.handler = (_) => pending.future;
    await mount(tester);
    await tester.enterText(find.byType(TextField), 'Ruczaj');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpWidget(const SizedBox());
    pending.complete([const TransitPlace('Ruczaj', 50.06, 19.95)]);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
