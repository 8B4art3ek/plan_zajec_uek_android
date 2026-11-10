import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plan_zajec_uek/core/theme/app_theme.dart';
import 'package:plan_zajec_uek/data/datasources/transit_service.dart';
import 'package:plan_zajec_uek/domain/entities/transit_journey.dart';
import 'package:plan_zajec_uek/presentation/providers/transit_provider.dart';
import 'package:plan_zajec_uek/presentation/screens/travel/travel_screen.dart';
import 'transit_service_test.dart' show sampleJourney, sampleLeg;

class _Service extends TransitService {
  int placeCalls = 0, planCalls = 0;
  bool fail = false;
  TransitQuery? lastQuery;
  String? cursor;
  Completer<TransitResults>? pending;
  TransitResults? customResults;
  final placeQueries = <String>[];
  @override
  Future<List<TransitPlace>> searchPlaces(String text) async {
    placeCalls++;
    placeQueries.add(text);
    if (text.toLowerCase().contains('boch')) {
      return [
        const TransitPlace('Bochnia', 49.977352, 20.431532,
            description: 'Przystanek / stacja · Bochnia')
      ];
    }
    return [
      const TransitPlace('Ruczaj', 50.02693, 19.905182,
          description: 'Przystanek / stacja · Kraków')
    ];
  }

  @override
  Future<TransitResults> plan(TransitQuery query, {String? cursor}) async {
    planCalls++;
    lastQuery = query;
    this.cursor = cursor;
    if (pending != null) return pending!.future;
    if (fail) {
      throw const TransitException('Wyszukiwarka jest chwilowo niedostępna.');
    }
    if (customResults != null) return customResults!;
    return TransitResults([
      TransitJourney.fromJson(sampleJourney(legs: [
        sampleLeg(realtime: true),
        {
          ...sampleLeg(mode: 'WALK'),
          'startTime': '2026-11-10T08:30:00Z',
          'endTime': '2026-11-10T08:35:00Z',
          'from': {'name': 'Rondo Mogilskie'},
          'to': {'name': 'END'},
          'displayName': '',
          'agencyName': '',
          'headsign': '',
          'intermediateStops': []
        },
      ])
        ..['endTime'] = '2026-11-10T08:35:00Z')
    ], nextCursor: 'later');
  }
}

void main() {
  setUpAll(() async {
    for (final entry in {
      'sans-serif': const String.fromEnvironment('PREVIEW_FONT'),
      'Roboto': const String.fromEnvironment('PREVIEW_FONT'),
      'MaterialIcons': const String.fromEnvironment('PREVIEW_ICONS'),
    }.entries) {
      if (entry.value.isNotEmpty) {
        await (FontLoader(entry.key)
              ..addFont(
                  File(entry.value).readAsBytes().then(ByteData.sublistView)))
            .load();
      }
    }
  });
  late _Service service;
  final previewKey = GlobalKey();
  setUp(() => service = _Service());
  tearDown(() => service.close());
  Future<void> mount(WidgetTester tester,
      {double width = 360, double scale = 1}) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
        overrides: [transitServiceProvider.overrideWithValue(service)],
        child: MaterialApp(
            theme: AppTheme.themeFor(AppThemeKind.midnight),
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: RepaintBoundary(key: previewKey, child: child!)),
            home: const TravelScreen())));
    await tester.pumpAndSettle();
  }

  Future<void> origin(WidgetTester tester) async {
    await tester.enterText(
        find.descendant(
            of: find.byKey(const Key('transit-origin')),
            matching: find.byType(TextField)),
        'Ruczaj Kraków');
    expect(service.placeCalls, 0);
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ruczaj'));
    await tester.pumpAndSettle();
  }

  Future<void> search(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Szukaj połączeń'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Szukaj połączeń'));
    await tester.pumpAndSettle();
  }

  Future<void> preview(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('WRITE_PREVIEWS')) return;
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final boundary = previewKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/previews/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final size in [(320.0, 1.0), (320.0, 2.0), (1024.0, 1.0)]) {
    testWidgets(
        'native travel fits ${size.$1} scale ${size.$2}, searches and opens details',
        (tester) async {
      await mount(tester, width: size.$1, scale: size.$2);
      expect(service.placeCalls, 0);
      expect(service.planCalls, 0);
      expect(find.text('Szukaj w Jakdojade'), findsNothing);
      await preview(tester, 'travel-form-${size.$1}-${size.$2}');
      await origin(tester);
      await search(tester);
      expect(service.planCalls, 1);
      await tester.ensureVisible(find.text('Bez przesiadek'));
      await tester.pumpAndSettle();
      await preview(tester, 'travel-results-${size.$1}-${size.$2}');
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Bez przesiadek'));
      await tester.pumpAndSettle();
      expect(find.text('Szczegóły połączenia'), findsOneWidget);
      expect(find.text('Ruczaj → Kampus UEK'), findsOneWidget);
      await preview(tester, 'travel-details-${size.$1}-${size.$2}');
      await tester.scrollUntilVisible(
          find.text('Dane: Transitous i dostawcy'), 200);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'missing origin sends no query; errors recover without losing selected origin',
      (tester) async {
    await mount(tester);
    await search(tester);
    expect(service.planCalls, 0);
    await tester.ensureVisible(find.byKey(const Key('transit-origin')));
    await tester.pumpAndSettle();
    await origin(tester);
    service.fail = true;
    await search(tester);
    expect(
        find.text('Wyszukiwarka jest chwilowo niedostępna.'), findsOneWidget);
    service.fail = false;
    await search(tester);
    expect(find.text('Bez przesiadek'), findsOneWidget);
    expect(service.lastQuery!.origin.name, 'Ruczaj');
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets(
        'journey timeline cleans MLD endpoints and intermediate stops at scale $scale',
        (tester) async {
      const feed = 'pl-Koleje-Małopolskie-ald_';
      final bus = {
        ...sampleLeg(mode: 'BUS'),
        'displayName': 'A40',
        'agencyName': 'Małopolskie Linie Dowozowe',
        'headsign': 'Kraków MDA',
        'realTime': true,
        'scheduledStartTime': '2026-11-10T07:56:00Z',
        'scheduledEndTime': '2026-11-10T08:26:00Z',
        'from': {
          'name': 'Borek Fałęcki 2132',
          'stopId': '${feed}borek-falecki2131-x4otj'
        },
        'to': {
          'name': 'Kraków MDA 656',
          'stopId': '${feed}krakow-mda656-xwzrr'
        },
        'intermediateStops': [
          {
            'name': 'Łagiewniki 2141',
            'stopId': '${feed}lagiewniki2141-xyz',
            'arrival': '2026-11-10T08:03:00Z',
            'scheduledArrival': '2026-11-10T07:59:00Z',
          },
          {
            'name': 'Rondo Matecznego 2144',
            'stopId': '${feed}rondo-matecznego2144-xyz'
          },
          {
            'name': 'Jubilat 4507',
            'stopId': '${feed}jubilat4507-xyz',
            'arrival': '2026-11-10T08:10:00Z'
          },
        ],
      };
      service.customResults = TransitResults([
        TransitJourney.fromJson(sampleJourney(legs: [bus]))
      ]);
      await mount(tester, scale: scale);
      await origin(tester);
      await search(tester);
      await tester.ensureVisible(find.text('Bez przesiadek'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bez przesiadek'));
      await tester.pumpAndSettle();
      expect(find.text('Borek Fałęcki'), findsOneWidget);
      expect(find.text('Kraków MDA'), findsOneWidget);
      expect(find.text('Borek Fałęcki 2132'), findsNothing);
      expect(tester.widget<Text>(find.text('08:56')).style!.decoration,
          TextDecoration.lineThrough);
      expect(tester.widget<Text>(find.text('09:26')).style!.decoration,
          TextDecoration.lineThrough);
      expect(find.text('Na żywo · +4 min'), findsOneWidget);
      await preview(tester, 'travel-timeline-$scale');
      await tester.ensureVisible(find.text('Przystanki po drodze (3)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Przystanki po drodze (3)'));
      await tester.pumpAndSettle();
      expect(find.text('Łagiewniki'), findsOneWidget);
      expect(find.text('Łagiewniki 2141'), findsNothing);
      expect(tester.widget<Text>(find.text('08:59')).style!.decoration,
          TextDecoration.lineThrough);
      expect(find.text('09:03'), findsOneWidget);
      await tester.ensureVisible(find.text('Rondo Matecznego'));
      await tester.pumpAndSettle();
      await preview(tester, 'travel-timeline-stops-$scale');
      expect(tester.takeException(), isNull);
    });
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets(
        'both autocomplete menus remain usable with keyboard at scale $scale',
        (tester) async {
      await mount(tester, width: 360, scale: scale);
      tester.view.viewInsets = const FakeViewPadding(bottom: 240);
      addTearDown(tester.view.resetViewInsets);
      final originField = find.descendant(
          of: find.byKey(const Key('transit-origin')),
          matching: find.byType(TextField));
      await tester.enterText(originField, 'Ruczaj');
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(originField).focusNode!.hasFocus, isTrue);
      await preview(tester, 'travel-origin-suggestions-$scale');
      await tester.tap(find.text('Ruczaj').last);
      await tester.pumpAndSettle();
      final destinationField = find.descendant(
          of: find.byKey(const Key('transit-destination')),
          matching: find.byType(TextField));
      await tester.enterText(destinationField, 'Boch');
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(destinationField).focusNode!.hasFocus,
          isTrue);
      await preview(tester, 'travel-destination-suggestions-$scale');
      await tester.tap(find.text('Bochnia'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'pagination retains query and changing filters clears stale results',
      (tester) async {
    await mount(tester);
    await origin(tester);
    await search(tester);
    final query = service.lastQuery;
    await tester.ensureVisible(find.text('Późniejsze'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Późniejsze'));
    await tester.pumpAndSettle();
    expect(service.cursor, 'later');
    expect(identical(query, service.lastQuery), isTrue);
    await tester.ensureVisible(find.text('Opcje podróży'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Opcje podróży'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Kolej'));
    await tester.pumpAndSettle();
    await tester.tap(find.ancestor(
        of: find.text('Kolej'), matching: find.byType(FilterChip)));
    await tester.pumpAndSettle();
    expect(find.text('Bez przesiadek'), findsNothing);
    expect(service.planCalls, 2);
  });

  testWidgets(
      'double tap does not duplicate requests and disposal during loading is safe',
      (tester) async {
    await mount(tester);
    await origin(tester);
    service.pending = Completer<TransitResults>();
    await tester.ensureVisible(find.text('Szukaj połączeń'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Szukaj połączeń'));
    await tester.pump();
    await tester.tap(find.text('Szukaj połączeń'));
    await tester.pump();
    expect(service.planCalls, 1);
    await tester.pumpWidget(const SizedBox());
    service.pending!.complete(const TransitResults([]));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'destination autocomplete and swap use selected places, never old coordinates',
      (tester) async {
    await mount(tester);
    await origin(tester);
    final destination = find.descendant(
        of: find.byKey(const Key('transit-destination')),
        matching: find.byType(TextField));
    await tester.enterText(destination, 'Boch');
    await search(tester);
    expect(service.planCalls, 0);
    expect(
        find.text('Wybierz miejsce docelowe z podpowiedzi.'), findsOneWidget);
    await tester.ensureVisible(destination);
    await tester.pumpAndSettle();
    await tester.tap(destination);
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bochnia'));
    await tester.pumpAndSettle();
    await search(tester);
    expect(service.lastQuery!.destination.name, 'Bochnia');
    expect(service.lastQuery!.destination.coordinates, '49.977352,20.431532');
    await tester.ensureVisible(find.byTooltip('Zamień początek z celem'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Zamień początek z celem'));
    await tester.pumpAndSettle();
    expect(find.text('Bez przesiadek'), findsNothing);
    await search(tester);
    expect(service.lastQuery!.origin.name, 'Bochnia');
    expect(service.lastQuery!.destination.name, 'Ruczaj');
    expect(service.placeCalls, 2);
  });
}
