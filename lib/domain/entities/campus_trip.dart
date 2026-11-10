import 'package:intl/intl.dart';

enum CampusDestination {
  campus('Kampus UEK', 'Rakowicka 27, Kraków'),
  railway('Kraków Główny · stacja kolejowa', 'Kraków Główny'),
  tunnel('Dworzec Główny Tunel', 'Dworzec Główny Tunel'),
  uek('UEK · przystanek', 'Uniwersytet Ekonomiczny'),
  mogilskie('Rondo Mogilskie', 'Rondo Mogilskie'),
  west('Dworzec Główny Zachód', 'Dworzec Główny Zachód'),
  east('Dworzec Główny Wschód', 'Dworzec Główny Wschód');

  const CampusDestination(this.label, this.queryName);
  final String label;
  final String queryName;
}

enum TripTransport { bus, tram, train }

Uri campusTripLink({
  required String origin,
  required CampusDestination destination,
  required DateTime dateTime,
  required bool arriveBy,
  required Set<TripTransport> transport,
}) {
  final start = origin.trim();
  if (start.isEmpty ||
      start.length > 200 ||
      RegExp(r'[\x00-\x1F]').hasMatch(start)) {
    throw ArgumentError.value(origin, 'origin');
  }
  if (transport.isEmpty) throw ArgumentError.value(transport, 'transport');
  final excluded = [
    if (!transport.contains(TripTransport.bus)) ...['bus', 'microbus'],
    if (!transport.contains(TripTransport.tram)) 'tram',
    if (!transport.contains(TripTransport.train)) 'train',
  ];
  // Official Jakdojade URL parameters. Place names are resolved by the planner;
  // no private API key, example API responses or guessed stop IDs are used.
  return Uri(
    scheme: 'https',
    host: 'jakdojade.pl',
    pathSegments: ['krakow', start, destination.queryName],
    queryParameters: {
      'fn': start,
      'tn': destination.queryName,
      'd': DateFormat('dd.MM.yy').format(dateTime),
      'h': DateFormat('HH:mm').format(dateTime),
      'ia': '$arriveBy',
      if (excluded.isNotEmpty) 'apv': excluded.join(','),
    },
  );
}
