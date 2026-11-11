import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plan_zajec_uek/data/datasources/transit_service.dart';
import 'package:plan_zajec_uek/domain/entities/campus_trip.dart';
import 'package:plan_zajec_uek/domain/entities/transit_journey.dart';

Map<String, dynamic> sampleLeg(
        {String mode = 'TRAM',
        bool realtime = false,
        bool cancelled = false}) =>
    {
      'mode': mode,
      'from': {'name': 'Ruczaj', 'track': '02'},
      'to': {'name': 'Rondo Mogilskie'},
      'startTime': '2026-11-10T08:00:00Z',
      'endTime': '2026-11-10T08:30:00Z',
      'scheduledStartTime': '2026-11-10T07:55:00Z',
      'displayName': '12',
      'headsign': 'Rondo Mogilskie',
      'agencyName': 'MPK Kraków',
      'realTime': realtime,
      'cancelled': cancelled,
      'distance': 120,
      'intermediateStops': [
        {'name': 'Most Grunwaldzki'}
      ],
    };
Map<String, dynamic> sampleJourney({List<Map<String, dynamic>>? legs}) => {
      'startTime': '2026-11-10T08:00:00Z',
      'endTime': '2026-11-10T08:30:00Z',
      'transfers': 0,
      'legs': legs ?? [sampleLeg()],
    };
final sampleQuery = TransitQuery(
    origin: const TransitPlace('Ruczaj', 50.02693, 19.905182),
    destination: campusPlace(CampusDestination.campus),
    time: transitTime(DateTime(2026, 11, 10), 10, 0)
        .add(const Duration(microseconds: 123456)),
    arriveBy: true,
    modes: {TripTransport.train});

void main() {
  test('line codes stay separate from train service names', () {
    TransitLeg train(String line, String display, String? service) =>
        TransitLeg.fromJson({
          ...sampleLeg(mode: 'LONG_DISTANCE'),
          'routeShortName': line,
          'displayName': display,
          'tripShortName': service,
        });
    final named = train('IC', 'IC 1312 Malinowski', '1312 Malinowski');
    expect(named.line, 'IC');
    expect(named.trainServiceLabel, 'IC Malinowski');
    expect(train('K5', 'K5 30505 Kasprowy', null).trainServiceLabel,
        'K5 Kasprowy');
    expect(train('K5', 'K5', '30505').trainServiceLabel, 'K5 30505');
    expect(train('IC', 'IC', null).trainServiceLabel, isNull);
    expect(
        TransitLeg.fromJson({
          ...sampleLeg(mode: 'BUS'),
          'routeShortName': '265',
          'displayName': '265 Borek',
        }).line,
        '265');
  });

  test(
      'MLD technical stop suffixes are hidden without changing IDs or other sources',
      () {
    const feed = 'pl-Koleje-Małopolskie-ald_';
    final cases = [
      ('Borek Fałęcki 2132', 'borek-falecki2131-x4otj', 'Borek Fałęcki'),
      ('Kraków MDA 656', 'krakow-mda656-xwzrr', 'Kraków MDA'),
      ('Łagiewniki 2141', 'lagiewniki2141-xyz', 'Łagiewniki'),
      ('Rondo Matecznego 2144', 'rondo-matecznego2144-xyz', 'Rondo Matecznego'),
      ('Osiedle 1000 2132', 'osiedle-10002132-xyz', 'Osiedle 1000'),
      (
        'Aleja 29 Listopada 4514',
        'aleja-29-listopada4514-xyz',
        'Aleja 29 Listopada'
      ),
    ];
    for (final entry in cases) {
      final stop = {'name': entry.$1, 'stopId': '$feed${entry.$2}'};
      expect(transitStopName(stop), entry.$3);
      expect(stop['name'], entry.$1);
      expect(stop['stopId'], '$feed${entry.$2}');
    }
    expect(
        transitStopName({
          'name': 'Dywizjonu 303',
          'stopId': '${feed}dywizjonu-3034514-xyz'
        }),
        'Dywizjonu 303');
    expect(
        transitStopName(
            {'name': 'Osiedle 1000', 'stopId': '${feed}osiedle-10004514-xyz'}),
        'Osiedle 1000');
    expect(
        transitStopName(
            {'name': 'Dywizjonu 303', 'stopId': 'pl-ZTP-Kraków_123'}),
        'Dywizjonu 303');
    expect(transitStopName({'name': 'Osiedle 1000', 'id': 'node/123'}),
        'Osiedle 1000');
    expect(transitStopName({'name': 'Szkoła 12'}), 'Szkoła 12');
    expect(
        TransitPlace.fromJson({
          'name': 'Kraków MDA 656',
          'id': '${feed}krakow-mda656-xwzrr',
          'lat': 50.06788,
          'lon': 19.94938
        }).name,
        'Kraków MDA');
  });

  test(
      'intermediate stop times use Polish timezone and missing times stay absent',
      () {
    expect(transitStopTime({'arrival': '2026-11-12T11:11:00Z'})!.hour, 12);
    expect(transitStopTime({'departure': '2026-07-12T11:11:00Z'})!.hour, 13);
    expect(transitStopTime({'name': 'Bez godziny'}), isNull);
    expect(transitStopTime({'arrival': 'bad'}), isNull);
    final stop = {
      'arrival': '2026-11-12T11:10:00Z',
      'departure': '2026-11-12T11:11:00Z',
      'scheduledArrival': '2026-11-12T11:05:00Z',
      'scheduledDeparture': '2026-11-12T11:07:00Z'
    };
    expect(transitStopTime(stop)!.minute, 11);
    expect(transitStopTime(stop, scheduled: true)!.minute, 7);
    expect(
        transitStopTime({'arrival': '2026-11-12T11:10:00Z'}, scheduled: true),
        isNull);
    expect(
        transitStopTime(
                {'arrival': null, 'scheduledArrival': '2026-11-12T11:10:00Z'})!
            .minute,
        10);
  });

  test(
      'geocoding is explicit, cached, Polish, and sends identification without account data',
      () async {
    var calls = 0;
    final service = TransitService(client: MockClient((request) async {
      calls++;
      expect(request.url.host, 'api.transitous.org');
      expect(request.url.path, '/api/v1/geocode');
      expect(request.url.queryParameters['text'], 'Kraków Główny');
      expect(request.headers['User-Agent'], contains('github.com/8B4art3ek'));
      expect(request.headers.keys.map((k) => k.toLowerCase()),
          isNot(contains('cookie')));
      expect(request.headers.keys.map((k) => k.toLowerCase()),
          isNot(contains('authorization')));
      return http.Response(
          jsonEncode([
            {
              'name': 'Kraków Główny',
              'lat': 50.06,
              'lon': 19.94,
              'type': 'STOP',
              'id': 'pl-PKP-Intercity_80416_parent',
              'country': 'PL',
              'areas': [
                {'name': 'Kraków', 'default': true}
              ]
            },
            {'name': 'Foreign match', 'lat': 51, 'lon': 10, 'country': 'DE'},
          ]),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }));
    addTearDown(service.close);
    final places = await service.searchPlaces(' Kraków Główny ');
    expect(places.single.name, 'Kraków Główny');
    expect(places.single.stopId, 'pl-PKP-Intercity_80416_parent');
    expect(places.single.description, contains('Kraków'));
    await service.searchPlaces('Kraków Główny');
    expect(calls, 1);
    await expectLater(
        service.searchPlaces('a'), throwsA(isA<TransitException>()));
    expect(calls, 1);
  });

  test(
      'routing preserves query, timezone, rail mode, cursor and direct walking legs',
      () async {
    var calls = 0;
    final service = TransitService(client: MockClient((request) async {
      calls++;
      expect(request.url.path, '/api/v6/plan');
      final p = request.url.queryParameters;
      expect(p['transitModes'], 'RAIL');
      expect(p['arriveBy'], 'true');
      expect(p['time'], '2026-11-10T09:00:00Z');
      expect(p['maxPreTransitTime'], '1800');
      expect(p['maxPostTransitTime'], '1800');
      expect(p['toPlace'], campusPlace(CampusDestination.campus).coordinates);
      expect(p['pageCursor'], calls == 1 ? isNull : 'next+%=/');
      return http.Response(
          jsonEncode({
            'itineraries': [sampleJourney()],
            'direct': [
              sampleJourney(legs: [sampleLeg(mode: 'WALK')])
            ],
            'nextPageCursor': 'next+%=/',
            'previousPageCursor': ''
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }));
    addTearDown(service.close);
    final first = await service.plan(sampleQuery);
    expect(first.journeys, hasLength(2));
    expect(first.journeys.last.legs.single.walking, isTrue);
    expect(first.previousCursor, isNull);
    final second = await service.plan(sampleQuery, cursor: first.nextCursor);
    expect(second.journeys, hasLength(1));
  });

  test('routing uses station IDs for stops and coordinates for addresses',
      () async {
    final station = TransitPlace.fromJson({
      'type': 'STOP',
      'id': 'pl-Polish-Trains_258460',
      'name': 'Kraków Sanktuarium',
      'lat': 50.013817,
      'lon': 19.934296,
    });
    final address = TransitPlace.fromJson({
      'type': 'ADDRESS',
      'id': 'node/1234',
      'name': 'Rakowicka 27',
      'lat': 50.0691863,
      'lon': 19.9569444,
    });
    final railway = campusPlace(CampusDestination.railway);
    final endpoints = <(String?, String?)>[];
    final service = TransitService(client: MockClient((request) async {
      final parameters = request.url.queryParameters;
      endpoints.add((parameters['fromPlace'], parameters['toPlace']));
      return http.Response('{"itineraries":[],"direct":[]}', 200);
    }));
    addTearDown(service.close);
    for (final (from, to) in [
      (station, railway),
      (station, address),
      (address, railway)
    ]) {
      await service.plan(TransitQuery(
          origin: from,
          destination: to,
          time: sampleQuery.time,
          arriveBy: false,
          modes: {TripTransport.train}));
    }
    expect(endpoints, [
      ('pl-Polish-Trains_258460', 'pl-PKP-Intercity_80416_parent'),
      ('pl-Polish-Trains_258460', address.coordinates),
      (address.coordinates, 'pl-PKP-Intercity_80416_parent'),
    ]);
    expect(campusPlace(CampusDestination.campus).stopId, isNull);
  });

  test(
      'transport filters use API mode families and empty filters do not send requests',
      () async {
    var calls = 0;
    final modes = {TripTransport.bus, TripTransport.tram};
    final query = TransitQuery(
        origin: sampleQuery.origin,
        destination: sampleQuery.destination,
        time: sampleQuery.time,
        arriveBy: false,
        modes: modes);
    modes.clear();
    final service = TransitService(client: MockClient((request) async {
      calls++;
      expect(request.url.queryParameters['transitModes'], 'BUS,COACH,TRAM');
      return http.Response('{"itineraries":[],"direct":[]}', 200);
    }));
    addTearDown(service.close);
    expect((await service.plan(query)).journeys, isEmpty);
    await expectLater(
        service.plan(TransitQuery(
            origin: query.origin,
            destination: query.destination,
            time: query.time,
            arriveBy: false,
            modes: {})),
        throwsA(isA<TransitException>()));
    expect(calls, 1);
  });

  for (final code in [400, 401, 404, 429, 500, 503]) {
    test(
        'HTTP $code returns a safe error without retry storms or raw server data',
        () async {
      var calls = 0;
      final service = TransitService(client: MockClient((_) async {
        calls++;
        return http.Response('private server response', code);
      }));
      addTearDown(service.close);
      await expectLater(
          service.plan(sampleQuery),
          throwsA(isA<TransitException>().having(
              (e) => e.message, 'safe message', isNot(contains('private')))));
      expect(calls, 1);
    });
  }

  for (final response in [
    '<html>maintenance</html>',
    '{}',
    '{"itineraries":[{}]}'
  ]) {
    test('malformed response is not shown as a valid empty result: $response',
        () async {
      final service = TransitService(
          client: MockClient((_) async => http.Response(response, 200)));
      addTearDown(service.close);
      await expectLater(
          service.plan(sampleQuery), throwsA(isA<TransitException>()));
    });
  }

  test('timeouts produce a recoverable message', () async {
    final service = TransitService(
        client: MockClient((_) => throw TimeoutException('test')));
    addTearDown(service.close);
    await expectLater(
        service.plan(sampleQuery),
        throwsA(isA<TransitException>()
            .having((e) => e.message, 'message', contains('zbyt długo'))));
  });

  test('responses from the wrong search day are rejected rather than displayed',
      () async {
    final service = TransitService(
        client: MockClient((_) async => http.Response(
            jsonEncode({
              'itineraries': [sampleJourney()],
              'direct': []
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'})));
    addTearDown(service.close);
    final departure = TransitQuery(
        origin: sampleQuery.origin,
        destination: sampleQuery.destination,
        time: sampleQuery.time,
        arriveBy: false,
        modes: sampleQuery.modes);
    await expectLater(
        service.plan(departure),
        throwsA(isA<TransitException>().having(
            (e) => e.message, 'message', contains('spoza wybranego terminu'))));
  });

  test(
      'Polish timezone is independent of device timezone, including summer and winter',
      () {
    expect(transitTime(DateTime(2026, 7, 10), 9, 30).toUtc(),
        DateTime.utc(2026, 7, 10, 7, 30));
    expect(transitTime(DateTime(2026, 11, 10), 9, 30).toUtc(),
        DateTime.utc(2026, 11, 10, 8, 30));
    final leg = TransitLeg.fromJson(sampleLeg(realtime: true, cancelled: true));
    expect(leg.start.hour, 9);
    expect(leg.start.difference(leg.scheduledStart).inMinutes, 5);
    expect(leg.realtime, isTrue);
    expect(leg.cancelled, isTrue);
    expect(leg.stops.single['name'], 'Most Grunwaldzki');
    expect(travelDuration(const Duration(minutes: 90)), '1 godz. 30 min');
  });
}
