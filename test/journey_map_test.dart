import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_polyline_algorithm/google_polyline_algorithm.dart';
import 'package:latlong2/latlong.dart';
import 'package:plan_zajec_uek/domain/entities/transit_journey.dart';
import 'package:plan_zajec_uek/presentation/screens/travel/journey_map_screen.dart';
import 'transit_service_test.dart' show sampleJourney, sampleLeg;

class _LocalTiles extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      const AssetImage('assets/branding/app_icon.png');
}

const _rail = [
  [50.013817, 19.934296],
  [50.042135, 19.953685],
  [50.068615, 19.947803]
];
const _walk = [
  [50.068615, 19.947803],
  [50.0689, 19.951],
  [50.069186, 19.956944]
];

Map<String, Object> _geometry(List<List<num>> points) => {
      'points': encodePolyline(points, accuracyExponent: 6),
      'precision': 6,
    };

void main() {
  test('decodes detailed MOTIS geometry at its declared precision', () {
    final leg =
        TransitLeg.fromJson({...sampleLeg(), 'legGeometry': _geometry(_rail)});
    expect(leg.geometry, [for (final pair in _rail) LatLng(pair[0], pair[1])]);
    for (final malformed in [
      null,
      {'points': '~', 'precision': 6},
      {'points': '???', 'precision': 6}
    ]) {
      expect(
          TransitLeg.fromJson({...sampleLeg(), 'legGeometry': malformed})
              .geometry,
          isEmpty);
    }
  });

  for (final (size, scale) in [
    (const Size(320, 640), 2.0),
    (const Size(1024, 768), 1.0)
  ]) {
    testWidgets('fits all journey legs at $size and restores camera after pan',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final journey = TransitJourney.fromJson(sampleJourney(legs: [
        {...sampleLeg(mode: 'REGIONAL_RAIL'), 'legGeometry': _geometry(_rail)},
        {...sampleLeg(mode: 'WALK'), 'legGeometry': _geometry(_walk)},
      ]));
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!),
        home: JourneyMapScreen(
            journey: journey,
            origin: 'Kraków Sanktuarium',
            destination: 'Kampus UEK',
            tileProvider: _LocalTiles()),
      ));
      await tester.pumpAndSettle();
      final map = find.byType(FlutterMap);
      final controller = tester.widget<FlutterMap>(map).mapController!;
      final polylines =
          tester.widget<PolylineLayer>(find.byType(PolylineLayer)).polylines;
      expect(polylines, hasLength(2));
      expect(polylines.first.points, journey.legs.first.geometry);
      expect(polylines.last.pattern.spacingFactor, isNotNull);
      expect(
          controller.camera.visibleBounds
              .contains(const LatLng(50.013817, 19.934296)),
          isTrue);
      expect(
          controller.camera.visibleBounds
              .contains(const LatLng(50.069186, 19.956944)),
          isTrue);
      expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
      final center = controller.camera.center;
      await tester.drag(map, const Offset(75, 30));
      await tester.pumpAndSettle();
      expect(controller.camera.center, isNot(center));
      await tester.tap(find.byTooltip('Pokaż całą trasę'));
      await tester.pumpAndSettle();
      expect(controller.camera.center, center);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('missing geometry keeps stop pins without inventing a line',
      (tester) async {
    final journey = TransitJourney.fromJson(sampleJourney(legs: [
      {
        ...sampleLeg(),
        'from': {'lat': 50.01, 'lon': 19.94},
        'to': {'lat': 50.06, 'lon': 19.95}
      },
    ]));
    await tester.pumpWidget(MaterialApp(
        home: JourneyMapScreen(
            journey: journey,
            origin: 'Początek',
            destination: 'Cel',
            tileProvider: _LocalTiles())));
    await tester.pumpAndSettle();
    expect(tester.widget<PolylineLayer>(find.byType(PolylineLayer)).polylines,
        isEmpty);
    expect(tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers,
        hasLength(2));
    expect(find.text('Brak przebiegu niektórych odcinków.'), findsOneWidget);
  });
}
