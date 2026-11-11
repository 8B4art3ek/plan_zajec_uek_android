import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../domain/entities/transit_journey.dart';

class JourneyMapScreen extends StatefulWidget {
  const JourneyMapScreen(
      {super.key,
      required this.journey,
      required this.origin,
      required this.destination,
      this.tileProvider});

  final TransitJourney journey;
  final String origin, destination;
  final TileProvider? tileProvider;

  @override
  State<JourneyMapScreen> createState() => _JourneyMapScreenState();
}

class _JourneyMapScreenState extends State<JourneyMapScreen> {
  final _controller = MapController();
  bool _tileFailed = false;
  late final _tiles = widget.tileProvider ??
      NetworkTileProvider(
          headers: {
            'User-Agent':
                'NiezbednikStudenta (https://github.com/8B4art3ek/plan_zajec_uek_android)'
          },
          cachingProvider: BuiltInMapCachingProvider.getOrCreateInstance(
              maxCacheSize: 80 * 1024 * 1024));
  late final _legs = widget.journey.legs;
  late final _stops = _buildStops();
  late final _points =
      {..._legs.expand((leg) => leg.geometry), ..._stops.keys}.toList();
  late final _fit = _points.length < 2
      ? null
      : CameraFit.coordinates(
          coordinates: _points, padding: const EdgeInsets.all(42), maxZoom: 17);

  Color _color(TransitLeg leg) => switch (leg.label) {
        'Autobus' => const Color(0xFF145ABA),
        'Tramwaj' => const Color(0xFF9C266A),
        'Pociąg' => const Color(0xFF00746C),
        'Metro' => const Color(0xFF9E4D12),
        _ => const Color(0xFF45556A),
      };

  LatLng? _endpoint(TransitLeg leg, {required bool start}) =>
      transitMapPoint(start ? leg.from : leg.to) ??
      (leg.geometry.isEmpty
          ? null
          : start
              ? leg.geometry.first
              : leg.geometry.last);

  Map<LatLng, (String, IconData)> _buildStops() {
    final stops = <LatLng, (String, IconData)>{};
    for (final leg in _legs.where((leg) => !leg.walking)) {
      for (final start in [true, false]) {
        final point = _endpoint(leg, start: start);
        if (point != null) {
          stops[point] = (
            transitStopName(start ? leg.from : leg.to),
            Icons.stop_circle_outlined
          );
        }
      }
    }
    final start = _endpoint(_legs.first, start: true);
    final end = _endpoint(_legs.last, start: false);
    if (start != null) {
      stops[start] = ('Start: ${widget.origin}', Icons.trip_origin);
    }
    if (end != null) {
      stops[end] = ('Cel: ${widget.destination}', Icons.flag_outlined);
    }
    return stops;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _attribution() async {
    try {
      if (await launchUrl(Uri.parse('https://www.openstreetmap.org/copyright'),
          mode: LaunchMode.externalApplication)) {
        return;
      }
    } catch (_) {/* Keep the map usable without a browser. */}
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Nie udało się otworzyć strony OpenStreetMap.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final modes = {for (final leg in _legs) leg.label: _color(leg)};
    return Scaffold(
      appBar: AppBar(title: const Text('Mapa przejazdu'), actions: [
        if (_points.isNotEmpty)
          IconButton(
              tooltip: 'Pokaż całą trasę',
              icon: const Icon(Icons.fit_screen_outlined),
              onPressed: () {
                if (_fit case final fit?) {
                  _controller.fitCamera(fit);
                } else {
                  _controller.move(_points.first, 16);
                }
              }),
      ]),
      body: _points.isEmpty
          ? const Center(
              child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Brak danych mapy dla tego połączenia.',
                      textAlign: TextAlign.center)))
          : Column(children: [
              Expanded(
                  child: FlutterMap(
                mapController: _controller,
                options: MapOptions(
                    initialCenter: _points.first,
                    initialZoom: 16,
                    initialCameraFit: _fit,
                    minZoom: 3,
                    maxZoom: 19,
                    backgroundColor: theme.colorScheme.surfaceContainer,
                    interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.all & ~InteractiveFlag.rotate)),
                children: [
                  TileLayer(
                      userAgentPackageName: 'com.example.plan_zajec_uek',
                      urlTemplate: const String.fromEnvironment(
                          'JOURNEY_TILE_URL',
                          defaultValue:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
                      tileProvider: _tiles,
                      errorTileCallback: (_, __, ___) {
                        if (mounted && !_tileFailed) {
                          setState(() => _tileFailed = true);
                        }
                      },
                      panBuffer: 0,
                      keepBuffer: 1),
                  PolylineLayer(polylines: [
                    for (final leg
                        in _legs.where((leg) => leg.geometry.isNotEmpty))
                      Polyline(
                          points: leg.geometry,
                          color: _color(leg),
                          strokeWidth: 5,
                          borderStrokeWidth: 2,
                          borderColor: Colors.white,
                          pattern: leg.walking
                              ? const StrokePattern.dotted()
                              : const StrokePattern.solid()),
                  ]),
                  MarkerLayer(markers: [
                    for (final entry in _stops.entries)
                      Marker(
                          point: entry.key,
                          width: 40,
                          height: 40,
                          child: IconButton.filled(
                              tooltip: entry.value.$1,
                              iconSize: 18,
                              style: IconButton.styleFrom(
                                  backgroundColor: const Color(0xFF193748),
                                  foregroundColor: Colors.white),
                              icon: Icon(entry.value.$2),
                              onPressed: () => showModalBottomSheet<void>(
                                  context: context,
                                  builder: (context) => SafeArea(
                                      child: ListTile(
                                          leading: Icon(entry.value.$2),
                                          title: Text(entry.value.$1))))))
                  ]),
                ],
              )),
              SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Wrap(spacing: 14, runSpacing: 6, children: [
                            for (final entry in modes.entries)
                              Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(
                                    entry.key == 'Pieszo'
                                        ? Icons.more_horiz
                                        : Icons.horizontal_rule,
                                    size: 20,
                                    color: entry.value),
                                const SizedBox(width: 4),
                                Text(entry.key,
                                    style: theme.textTheme.bodySmall),
                              ]),
                          ]),
                          if (_legs.any((leg) => leg.geometry.isEmpty))
                            Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                    'Brak przebiegu niektórych odcinków.',
                                    style: theme.textTheme.bodySmall)),
                          if (_tileFailed)
                            Text('Nie udało się wczytać części tła mapy.',
                                style: theme.textTheme.bodySmall),
                          Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                  onPressed: _attribution,
                                  child: const Text(
                                      '© OpenStreetMap contributors'))),
                        ]),
                  )),
            ]),
    );
  }
}
