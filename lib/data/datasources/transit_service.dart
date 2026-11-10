import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../../domain/entities/campus_trip.dart';
import '../../domain/entities/transit_journey.dart';

class TransitException implements Exception {
  const TransitException(this.message);
  final String message;
  @override
  String toString() => message;
}

class TransitQuery {
  TransitQuery(
      {required this.origin,
      required this.destination,
      required this.time,
      required this.arriveBy,
      this.maxWalkMinutes = 30,
      required Set<TripTransport> modes})
      : modes = Set.unmodifiable(modes);
  final TransitPlace origin, destination;
  final DateTime time;
  final bool arriveBy;
  final int maxWalkMinutes;
  final Set<TripTransport> modes;
}

class TransitService {
  TransitService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  final _places = <String, List<TransitPlace>>{};
  static const _headers = {
    'Accept': 'application/json',
    'User-Agent': 'NiezbednikStudenta/1.0.10-beta.1 '
        '(https://github.com/8B4art3ek/plan_zajec_uek_android)',
  };

  void close() => _client.close();

  Future<dynamic> _get(String path, Map<String, String> parameters) async {
    try {
      final response = await _client
          .get(Uri.https('api.transitous.org', '/api/$path', parameters),
              headers: _headers)
          .timeout(const Duration(seconds: 25));
      if (response.statusCode == 429) {
        throw const TransitException(
            'Limit zapytań został osiągnięty. Spróbuj ponownie później.');
      }
      if (response.statusCode >= 500) {
        throw const TransitException(
            'Wyszukiwarka połączeń jest chwilowo niedostępna. Spróbuj ponownie później.');
      }
      if (response.statusCode == 400 || response.statusCode == 404) {
        throw const TransitException(
            'Nie można wyszukać tej trasy. Zmień miejsce lub termin podróży.');
      }
      if (response.statusCode != 200) {
        throw const TransitException(
            'Nie udało się pobrać połączeń. Spróbuj ponownie później.');
      }
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on TimeoutException {
      throw const TransitException(
          'Wyszukiwanie trwa zbyt długo. Spróbuj ponownie za chwilę.');
    } on SocketException {
      throw const TransitException(
          'Brak połączenia z internetem. Sprawdź sieć i ponów próbę.');
    } on HandshakeException {
      throw const TransitException(
          'Nie udało się nawiązać bezpiecznego połączenia z wyszukiwarką.');
    } on http.ClientException {
      throw const TransitException(
          'Nie udało się połączyć z wyszukiwarką. Sprawdź internet i ponów próbę.');
    } on FormatException {
      throw const TransitException(
          'Wyszukiwarka zwróciła nieprawidłowe dane. Spróbuj ponownie później.');
    }
  }

  Future<List<TransitPlace>> searchPlaces(String text) async {
    final query = text.trim();
    if (query.length < 3 ||
        query.length > 200 ||
        RegExp(r'[\x00-\x1F]').hasMatch(query)) {
      throw const TransitException('Wpisz od 3 do 200 znaków nazwy miejsca.');
    }
    if (_places.containsKey(query)) return _places[query]!;
    try {
      final data = await _get('v1/geocode', {
        'text': query,
        'language': 'pl',
        'place': '50.0691863,19.9569444',
        'numResults': '8'
      });
      final seen = <String>{};
      final places = (data as List)
          .cast<Map<String, dynamic>>()
          .where((item) => item['country'] == 'PL')
          .map(TransitPlace.fromJson)
          .where((place) => seen.add('${place.name}:${place.coordinates}'))
          .toList(growable: false);
      if (_places.length >= 20) _places.remove(_places.keys.first);
      _places[query] = places;
      return places;
    } on TransitException {
      rethrow;
    } catch (_) {
      throw const TransitException(
          'Nie udało się odczytać listy miejsc. Ponów próbę.');
    }
  }

  Future<TransitResults> plan(TransitQuery query, {String? cursor}) async {
    if (query.modes.isEmpty) {
      throw const TransitException(
          'Wybierz przynajmniej jeden środek transportu.');
    }
    if (![10, 15, 30].contains(query.maxWalkMinutes)) {
      throw const TransitException(
          'Wybierz czas dojścia: 10, 15 lub 30 minut.');
    }
    final modes = [
      if (query.modes.contains(TripTransport.bus)) ...['BUS', 'COACH'],
      if (query.modes.contains(TripTransport.tram)) 'TRAM',
      if (query.modes.contains(TripTransport.train)) 'RAIL'
    ];
    try {
      final data = await _get('v6/plan', {
        'fromPlace': query.origin.coordinates,
        'toPlace': query.destination.coordinates,
        // The live endpoint misreads fractional seconds despite its RFC3339 schema.
        'time':
            DateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'").format(query.time.toUtc()),
        'arriveBy': '${query.arriveBy}',
        'transitModes': modes.join(','),
        'directModes': 'WALK',
        'maxPreTransitTime': '${query.maxWalkMinutes * 60}',
        'maxPostTransitTime': '${query.maxWalkMinutes * 60}',
        'numItineraries': '5',
        'maxItineraries': '5',
        if (cursor != null) 'pageCursor': cursor,
      }) as Map<String, dynamic>;
      final journeys = [
        ...(data['itineraries'] as List),
        if (cursor == null) ...(data['direct'] as List? ?? []),
      ].cast<Map<String, dynamic>>().map(TransitJourney.fromJson).toList();
      journeys.sort((a, b) => a.start.compareTo(b.start));
      // Pagination legitimately leaves the original search window.
      if (cursor == null &&
          journeys.any((journey) => query.arriveBy
              ? journey.end.isAfter(query.time.add(const Duration(minutes: 1)))
              : journey.start
                  .isBefore(query.time.subtract(const Duration(minutes: 1))))) {
        throw const TransitException(
            'Wyszukiwarka zwróciła połączenia spoza wybranego terminu. Ponów wyszukiwanie.');
      }
      String? page(Object? value) =>
          value is String && value.isNotEmpty ? value : null;
      return TransitResults(journeys,
          nextCursor: page(data['nextPageCursor']),
          previousCursor: page(data['previousPageCursor']));
    } on TransitException {
      rethrow;
    } catch (_) {
      throw const TransitException(
          'Nie udało się odczytać połączeń. Ponów próbę później.');
    }
  }
}
