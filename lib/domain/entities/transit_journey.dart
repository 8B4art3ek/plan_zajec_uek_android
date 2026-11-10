import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'campus_trip.dart';

final _warsaw = () {
  tzdata.initializeTimeZones();
  return tz.getLocation('Europe/Warsaw');
}();

DateTime transitNow() => tz.TZDateTime.now(_warsaw);
DateTime transitTime(DateTime day, int hour, int minute) =>
    tz.TZDateTime(_warsaw, day.year, day.month, day.day, hour, minute);
DateTime _time(Object? value) =>
    tz.TZDateTime.from(DateTime.parse(value as String), _warsaw);

String transitStopName(Map<String, dynamic> place) {
  final name = (place['name'] as String? ?? 'Przystanek').trim();
  final id = (place['stopId'] ?? place['id'] ?? '') as String;
  // This feed appends internal stop codes to names, including merged platforms
  // whose name suffix can differ from the numeric part of the chosen stop ID.
  const feed = 'pl-Koleje-Małopolskie-ald_';
  if (!id.startsWith(feed)) return name;
  final suffix = RegExp(r'^(.*\S)\s+(\d{3,5})$').firstMatch(name);
  if (suffix == null) return name;
  final base = suffix[1]!;
  var slug = base.toLowerCase();
  const polish = 'ąćęłńóśźż', ascii = 'acelnoszz';
  for (var i = 0; i < polish.length; i++) {
    slug = slug.replaceAll(polish[i], ascii[i]);
  }
  slug = slug.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
  final isFeedCode = RegExp('^${RegExp.escape(slug)}' r'\d+-[a-z0-9]+$')
      .hasMatch(id.substring(feed.length));
  if (isFeedCode || place['stopCode']?.toString() == suffix[2]) return base;
  return name;
}

DateTime? transitStopTime(Map<String, dynamic> place,
    {bool scheduled = false}) {
  Object? value;
  var hasActual = false;
  for (final keys in [
    ('departure', 'scheduledDeparture'),
    ('arrival', 'scheduledArrival')
  ]) {
    if (place[keys.$1] is String) {
      hasActual = true;
      value = scheduled ? place[keys.$2] : place[keys.$1];
      break;
    }
  }
  if (!hasActual) {
    value = place['scheduledDeparture'] ?? place['scheduledArrival'];
  }
  if (value is! String) return null;
  try {
    return _time(value);
  } on FormatException {
    return null;
  }
}

class TransitPlace {
  const TransitPlace(this.name, this.lat, this.lon, {this.description = ''});
  final String name;
  final double lat;
  final double lon;
  final String description;
  String get coordinates => '$lat,$lon';

  factory TransitPlace.fromJson(Map<String, dynamic> json) {
    final lat = (json['lat'] as num).toDouble();
    final lon = (json['lon'] as num).toDouble();
    if (!lat.isFinite || !lon.isFinite || lat.abs() > 90 || lon.abs() > 180) {
      throw const FormatException('Invalid coordinates');
    }
    final areas = (json['areas'] as List? ?? [])
        .cast<Map<String, dynamic>>()
        .where((area) => area['default'] == true)
        .map((area) => area['name'] as String)
        .toSet();
    final address = [json['street'], json['houseNumber']]
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .join(' ');
    return TransitPlace(transitStopName(json), lat, lon,
        description: [
          if (json['type'] == 'STOP') 'Przystanek / stacja',
          if (address.isNotEmpty) address,
          ...areas
        ].join(' · '));
  }
}

// Coordinates verified against Transitous geocoding, not feed-specific stop IDs.
TransitPlace campusPlace(CampusDestination destination) =>
    switch (destination) {
      CampusDestination.campus =>
        const TransitPlace('Kampus UEK', 50.0691863, 19.9569444),
      CampusDestination.railway =>
        const TransitPlace('Kraków Główny', 50.068615, 19.947803),
      CampusDestination.tunnel =>
        const TransitPlace('Dworzec Główny Tunel', 50.068203, 19.947735),
      CampusDestination.uek =>
        const TransitPlace('Uniwersytet Ekonomiczny', 50.06756, 19.952206),
      CampusDestination.mogilskie =>
        const TransitPlace('Rondo Mogilskie', 50.06577, 19.95964),
      CampusDestination.west =>
        const TransitPlace('Dworzec Główny Zachód', 50.067688, 19.945341),
      CampusDestination.east =>
        const TransitPlace('Dworzec Główny Wschód', 50.06848, 19.94943),
    };

class TransitLeg {
  TransitLeg.fromJson(Map<String, dynamic> json)
      : mode = json['mode'] as String,
        from = json['from'] as Map<String, dynamic>,
        to = json['to'] as Map<String, dynamic>,
        start = _time(json['startTime']),
        end = _time(json['endTime']),
        scheduledStart = _time(json['scheduledStartTime'] ?? json['startTime']),
        scheduledEnd = _time(json['scheduledEndTime'] ?? json['endTime']),
        line = (json['displayName'] ?? json['routeShortName'] ?? '') as String,
        headsign = (json['headsign'] ?? '') as String,
        agency = (json['agencyName'] ?? '') as String,
        realtime = json['realTime'] == true,
        cancelled = json['cancelled'] == true,
        extended = json['loopedCalendarSince'] != null,
        staySeated = json['interlineWithPreviousLeg'] == true,
        distance = (json['distance'] as num?)?.round(),
        stops = (json['intermediateStops'] as List? ?? [])
            .cast<Map<String, dynamic>>() {
    if (end.isBefore(start)) throw const FormatException('Invalid leg times');
  }
  final String mode, line, headsign, agency;
  final Map<String, dynamic> from, to;
  final DateTime start, end, scheduledStart, scheduledEnd;
  final bool realtime, cancelled, extended, staySeated;
  final int? distance;
  final List<Map<String, dynamic>> stops;
  bool get walking => mode == 'WALK';
  Duration get duration => end.difference(start);
  String get label => switch (mode) {
        'WALK' => 'Pieszo',
        'TRAM' => 'Tramwaj',
        'BUS' || 'COACH' => 'Autobus',
        'SUBWAY' => 'Metro',
        'RAIL' ||
        'REGIONAL_RAIL' ||
        'REGIONAL_FAST_RAIL' ||
        'SUBURBAN' ||
        'HIGHSPEED_RAIL' ||
        'LONG_DISTANCE' ||
        'NIGHT_RAIL' =>
          'Pociąg',
        _ => 'Transport',
      };
}

class TransitJourney {
  TransitJourney.fromJson(Map<String, dynamic> json)
      : start = _time(json['startTime']),
        end = _time(json['endTime']),
        transfers = (json['transfers'] as num).toInt(),
        legs = (json['legs'] as List)
            .cast<Map<String, dynamic>>()
            .map(TransitLeg.fromJson)
            .toList() {
    if (legs.isEmpty || end.isBefore(start) || transfers < 0) {
      throw const FormatException('Invalid journey');
    }
  }
  final DateTime start, end;
  final int transfers;
  final List<TransitLeg> legs;
  Duration get duration => end.difference(start);
  bool get cancelled => legs.any((leg) => leg.cancelled);
}

class TransitResults {
  const TransitResults(this.journeys, {this.nextCursor, this.previousCursor});
  final List<TransitJourney> journeys;
  final String? nextCursor, previousCursor;
}

String travelDuration(Duration duration) {
  final minutes = (duration.inSeconds / 60).ceil();
  return minutes < 60
      ? '$minutes min'
      : '${minutes ~/ 60} godz.${minutes % 60 == 0 ? '' : ' ${minutes % 60} min'}';
}
