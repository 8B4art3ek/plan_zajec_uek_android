import 'package:google_polyline_algorithm/google_polyline_algorithm.dart';
import 'package:latlong2/latlong.dart';
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
  const TransitPlace(this.name, this.lat, this.lon,
      {this.description = '', this.stopId});
  final String name;
  final double lat;
  final double lon;
  final String description;
  final String? stopId;
  String get coordinates => '$lat,$lon';
  String get routingReference => stopId ?? coordinates;

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
    final id = json['id'];
    return TransitPlace(transitStopName(json), lat, lon,
        stopId: json['type'] == 'STOP' && id is String && id.trim().isNotEmpty
            ? id
            : null,
        description: [
          if (json['type'] == 'STOP') 'Przystanek / stacja',
          if (address.isNotEmpty) address,
          ...areas
        ].join(' · '));
  }
}

// Stop references and coordinates verified against Transitous geocoding.
TransitPlace campusPlace(CampusDestination destination) =>
    switch (destination) {
      CampusDestination.campus =>
        const TransitPlace('Kampus UEK', 50.0691863, 19.9569444),
      CampusDestination.railway => const TransitPlace(
          'Kraków Główny', 50.068615, 19.947803,
          stopId: 'pl-PKP-Intercity_80416_parent'),
      CampusDestination.tunnel => const TransitPlace(
          'Dworzec Główny Tunel', 50.068203, 19.947735,
          stopId: 'pl-ZTP-Kraków-T_stop_322_117319'),
      CampusDestination.uek => const TransitPlace(
          'Uniwersytet Ekonomiczny', 50.06756, 19.952206,
          stopId: 'pl-ZTP-Kraków-T_stop_205_12719'),
      CampusDestination.mogilskie => const TransitPlace(
          'Rondo Mogilskie', 50.06577, 19.95964,
          stopId: 'pl-ZTP-Kraków-T_stop_203_12519'),
      CampusDestination.west => const TransitPlace(
          'Dworzec Główny Zachód', 50.067688, 19.945341,
          stopId: 'pl-ZTP-Kraków-T_stop_335_260819'),
      CampusDestination.east => const TransitPlace(
          'Dworzec Główny Wschód', 50.06848, 19.94943,
          stopId: 'pl-ZTP-Kraków-A_8906'),
    };

LatLng? transitMapPoint(Map<String, dynamic> place) =>
    _mapPoint(place['lat'], place['lon']);

LatLng? _mapPoint(Object? lat, Object? lon) {
  if (lat is! num ||
      lon is! num ||
      !lat.isFinite ||
      !lon.isFinite ||
      lat.abs() > 85.051129 ||
      lon.abs() > 180) {
    return null;
  }
  return LatLng(lat.toDouble(), lon.toDouble());
}

List<LatLng> _decodeGeometry(Object? value) {
  if (value is! Map) return const [];
  final points = value['points'];
  final precision = value['precision'] ?? 6;
  if (points is! String ||
      points.isEmpty ||
      precision is! int ||
      precision < 5 ||
      precision > 7 ||
      points.codeUnits.any((unit) => unit < 63 || unit > 126)) {
    return const [];
  }
  try {
    final decoded = decodePolyline(points, accuracyExponent: precision);
    final path = <LatLng>[];
    for (final pair in decoded) {
      if (pair.length != 2) return const [];
      final point = _mapPoint(pair[0], pair[1]);
      if (point == null) return const [];
      path.add(point);
    }
    return path.length < 2 ? const [] : List.unmodifiable(path);
  } on RangeError {
    return const [];
  } on FormatException {
    return const [];
  }
}

class TransitLeg {
  TransitLeg.fromJson(Map<String, dynamic> json)
      : mode = json['mode'] as String,
        from = json['from'] as Map<String, dynamic>,
        to = json['to'] as Map<String, dynamic>,
        start = _time(json['startTime']),
        end = _time(json['endTime']),
        scheduledStart = _time(json['scheduledStartTime'] ?? json['startTime']),
        scheduledEnd = _time(json['scheduledEndTime'] ?? json['endTime']),
        _routeShortName = (json['routeShortName'] as String?)?.trim() ?? '',
        _displayName = (json['displayName'] as String?)?.trim() ?? '',
        _tripShortName = (json['tripShortName'] as String?)?.trim() ?? '',
        headsign = (json['headsign'] as String?)?.trim() ?? '',
        realtime = json['realTime'] == true,
        cancelled = json['cancelled'] == true,
        extended = json['loopedCalendarSince'] != null,
        staySeated = json['interlineWithPreviousLeg'] == true,
        distance = (json['distance'] as num?)?.round(),
        _encodedGeometry = json['legGeometry'],
        stops = (json['intermediateStops'] as List? ?? [])
            .cast<Map<String, dynamic>>() {
    if (end.isBefore(start)) throw const FormatException('Invalid leg times');
  }
  final String mode, headsign;
  final String _routeShortName, _displayName, _tripShortName;
  final Map<String, dynamic> from, to;
  final DateTime start, end, scheduledStart, scheduledEnd;
  final bool realtime, cancelled, extended, staySeated;
  final int? distance;
  final List<Map<String, dynamic>> stops;
  final Object? _encodedGeometry;
  late final List<LatLng> geometry = _decodeGeometry(_encodedGeometry);
  bool get walking => mode == 'WALK';
  String get line => _routeShortName.isEmpty ? _displayName : _routeShortName;

  String? get trainServiceLabel {
    if (label != 'Pociąg') return null;
    var service = _tripShortName;
    if (service.isEmpty &&
        _routeShortName.isNotEmpty &&
        _displayName.startsWith('$_routeShortName ')) {
      service = _displayName.substring(_routeShortName.length + 1);
    }
    if (service.isEmpty) return null;
    if (_routeShortName.isNotEmpty && service.startsWith('$_routeShortName ')) {
      service = service.substring(_routeShortName.length + 1);
    }
    // Named trains commonly include their individual run number in this field.
    service = service.replaceFirst(RegExp(r'^\d+\s+(?=\D)'), '');
    final title =
        _routeShortName.isEmpty ? service : '$_routeShortName $service';
    return title == line || service == _routeShortName ? null : title;
  }

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
