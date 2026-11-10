import 'dart:io';
import 'package:intl/intl.dart';
import 'package:plan_zajec_uek/data/datasources/transit_service.dart';
import 'package:plan_zajec_uek/domain/entities/campus_trip.dart';
import 'package:plan_zajec_uek/domain/entities/transit_journey.dart';

// Manual smoke check: four public requests, never part of automated tests.
Future<void> main() async {
  final service = TransitService();
  try {
    for (final origin in ['Ruczaj Kraków', 'Bochnia']) {
      final places = await service.searchPlaces(origin);
      if (places.isEmpty) throw StateError('No origin: $origin');
      final results = await service.plan(TransitQuery(
        origin: places.first,
        destination: campusPlace(CampusDestination.campus),
        time: transitNow().add(const Duration(minutes: 10)),
        arriveBy: false,
        modes: origin == 'Bochnia'
            ? {TripTransport.train}
            : TripTransport.values.toSet(),
      ));
      if (results.journeys.isEmpty) throw StateError('No routes: $origin');
      stdout.writeln('$origin: ${results.journeys.length} routes');
      for (final journey in results.journeys.take(2)) {
        stdout.writeln('${DateFormat('HH:mm').format(journey.start)} - '
            '${DateFormat('HH:mm').format(journey.end)}: '
            '${journey.legs.map((leg) => '${leg.mode} ${leg.line}').join(' > ')}');
      }
    }
  } finally {
    service.close();
  }
}
