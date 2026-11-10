import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/date_labels.dart';
import '../../../data/datasources/transit_service.dart';
import '../../../domain/entities/campus_trip.dart';
import '../../../domain/entities/transit_journey.dart';
import '../../providers/providers.dart';
import '../../providers/transit_provider.dart';
import '../../widgets/app_scroll_view.dart';
import '../../widgets/transit_place_field.dart';

String _clock(DateTime time) => DateFormat('HH:mm').format(time);
String _day(DateTime time) =>
    '${DateFormat('dd.MM.yyyy').format(time)} · ${polishWeekday(time)}';
IconData _modeIcon(TransitLeg leg) => switch (leg.mode) {
      'WALK' => Icons.directions_walk,
      'TRAM' => Icons.tram_outlined,
      'BUS' || 'COACH' => Icons.directions_bus_outlined,
      _ => Icons.train_outlined,
    };

class TransitPlannerScreen extends ConsumerStatefulWidget {
  const TransitPlannerScreen({super.key});
  @override
  ConsumerState<TransitPlannerScreen> createState() => _TransitPlannerState();
}

class _TransitPlannerState extends ConsumerState<TransitPlannerScreen> {
  TransitPlace? _origin;
  TransitPlace? _destination = campusPlace(CampusDestination.campus);
  DateTime _time = transitNow().add(const Duration(minutes: 5));
  bool _arriveBy = false, _busy = false;
  bool _timeEdited = false;
  int _maxWalkMinutes = 30;
  final _modes = TripTransport.values.toSet();
  TransitQuery? _query;
  TransitResults? _results;
  String? _error;

  void _change(VoidCallback change) => setState(() {
        change();
        _results = null;
        _query = null;
        _error = null;
      });

  void _swapPlaces() {
    FocusScope.of(context).unfocus();
    _change(() {
      final origin = _origin;
      _origin = _destination;
      _destination = origin;
    });
  }

  Future<void> _search({String? cursor}) async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    if (_origin == null || _destination == null || _modes.isEmpty) {
      setState(() => _error = _origin == null
          ? 'Wybierz miejsce początkowe.'
          : _destination == null
              ? 'Wybierz miejsce docelowe z podpowiedzi.'
              : 'Wybierz przynajmniej jeden środek transportu.');
      return;
    }
    if (cursor == null && !_timeEdited) {
      _time = transitNow().add(const Duration(minutes: 1));
    }
    final query = cursor != null
        ? _query!
        : TransitQuery(
            origin: _origin!,
            destination: _destination!,
            time: _time,
            arriveBy: _arriveBy,
            maxWalkMinutes: _maxWalkMinutes,
            modes: _modes);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final results =
          await ref.read(transitServiceProvider).plan(query, cursor: cursor);
      if (!mounted) return;
      setState(() {
        _query = query;
        _results = results;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is TransitException
            ? error.message
            : 'Nie udało się wyszukać połączeń. Ponów próbę.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _firstClass() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final date = ref.read(selectedDateProvider);
      final entries =
          await ref.read(scheduleRepositoryProvider).getEntriesForDate(date);
      final starts = <DateTime>[];
      for (final entry
          in entries.where((e) => !e.isMoved && !e.isReservation)) {
        final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(entry.startTime);
        if (match == null) continue;
        final hour = int.parse(match[1]!), minute = int.parse(match[2]!);
        if (hour < 24 && minute < 60) {
          starts.add(transitTime(entry.date, hour, minute));
        }
      }
      starts.sort();
      if (!mounted) return;
      if (starts.isEmpty) {
        setState(() => _error = 'Brak zajęć w wybranym dniu planu.');
      } else {
        final arrival = starts.first.subtract(const Duration(minutes: 10));
        if (arrival.isBefore(transitNow())) {
          setState(() => _error =
              'Ten termin już minął. Wybierz późniejszy dzień w planie.');
        } else {
          _change(() {
            _time = arrival;
            _timeEdited = true;
            _arriveBy = true;
            _destination = campusPlace(CampusDestination.campus);
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() =>
            _error = 'Nie udało się odczytać planu. Ustaw termin ręcznie.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _datePicker() async {
    final now = transitNow();
    final first = DateTime(now.year, now.month, now.day);
    final day = await showDatePicker(
        context: context,
        initialDate: _time.isBefore(first) ? first : _time,
        firstDate: first,
        lastDate: DateTime(now.year + 1, now.month, now.day));
    if (day != null && mounted) {
      _change(() {
        _time = transitTime(day, _time.hour, _time.minute);
        _timeEdited = true;
      });
    }
  }

  Future<void> _timePicker() async {
    final time = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(_time));
    if (time != null && mounted) {
      _change(() {
        _time = transitTime(_time, time.hour, time.minute);
        _timeEdited = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Dojazdy')),
        body: SafeArea(
            top: false,
            child: AppScrollView(
                child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Center(
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Expanded(
                                        child: Column(children: [
                                      TransitPlaceField(
                                          key: const Key('transit-origin'),
                                          label: 'Skąd',
                                          icon: Icons.trip_origin,
                                          value: _origin,
                                          enabled: !_busy,
                                          onChanged: (place) =>
                                              _change(() => _origin = place)),
                                      const SizedBox(height: 12),
                                      TransitPlaceField(
                                          key: const Key('transit-destination'),
                                          label: 'Dokąd',
                                          icon: Icons.location_on_outlined,
                                          value: _destination,
                                          enabled: !_busy,
                                          onChanged: (place) => _change(
                                              () => _destination = place)),
                                    ])),
                                    const SizedBox(width: 4),
                                    IconButton(
                                        tooltip: 'Zamień początek z celem',
                                        onPressed: _busy ? null : _swapPlaces,
                                        icon: const Icon(Icons.swap_vert)),
                                  ]),
                              const SizedBox(height: 8),
                              Align(
                                  alignment: Alignment.centerLeft,
                                  child: PopupMenuButton<CampusDestination>(
                                    enabled: !_busy,
                                    tooltip: 'Wybierz cel przy UEK',
                                    onSelected: (value) {
                                      FocusScope.of(context).unfocus();
                                      _change(() =>
                                          _destination = campusPlace(value));
                                    },
                                    itemBuilder: (_) => [
                                      for (final value
                                          in CampusDestination.values)
                                        PopupMenuItem(
                                            value: value,
                                            child: Text(value.label))
                                    ],
                                    child: const Padding(
                                        padding: EdgeInsets.symmetric(
                                            vertical: 10, horizontal: 4),
                                        child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.school_outlined,
                                                  size: 18),
                                              SizedBox(width: 8),
                                              Flexible(
                                                  child: Text('UEK i okolice')),
                                              Icon(Icons.arrow_drop_down),
                                            ])),
                                  )),
                              const SizedBox(height: 16),
                              SegmentedButton<bool>(
                                  showSelectedIcon: false,
                                  segments: const [
                                    ButtonSegment(
                                        value: false, label: Text('Odjazd')),
                                    ButtonSegment(
                                        value: true, label: Text('Przyjazd'))
                                  ],
                                  selected: {_arriveBy},
                                  onSelectionChanged: _busy
                                      ? null
                                      : (values) => _change(
                                          () => _arriveBy = values.single)),
                              const SizedBox(height: 12),
                              Wrap(spacing: 8, runSpacing: 8, children: [
                                OutlinedButton.icon(
                                    onPressed: _busy ? null : _datePicker,
                                    icon: const Icon(
                                        Icons.calendar_today_outlined,
                                        size: 18),
                                    label: Text(_day(_time))),
                                OutlinedButton.icon(
                                    onPressed: _busy ? null : _timePicker,
                                    icon: const Icon(Icons.schedule, size: 18),
                                    label: Text(_clock(_time))),
                                TextButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _change(() {
                                              _time = transitNow();
                                              _timeEdited = false;
                                              _arriveBy = false;
                                            }),
                                    child: const Text('Teraz')),
                              ]),
                              const SizedBox(height: 8),
                              ExpansionTile(
                                  key: const Key('transit-options'),
                                  tilePadding: EdgeInsets.zero,
                                  title: const Text('Opcje podróży'),
                                  leading: const Icon(Icons.tune),
                                  children: [
                                    TextButton.icon(
                                        onPressed: _busy ? null : _firstClass,
                                        icon: const Icon(
                                            Icons.event_available_outlined),
                                        label: const Text(
                                            '10 min przed pierwszymi zajęciami')),
                                    const SizedBox(height: 8),
                                    Wrap(spacing: 8, runSpacing: 4, children: [
                                      for (final item in [
                                        (
                                          TripTransport.bus,
                                          'Autobusy',
                                          Icons.directions_bus_outlined
                                        ),
                                        (
                                          TripTransport.tram,
                                          'Tramwaje',
                                          Icons.tram_outlined
                                        ),
                                        (
                                          TripTransport.train,
                                          'Kolej',
                                          Icons.train_outlined
                                        )
                                      ])
                                        FilterChip(
                                            label: Text(item.$2),
                                            showCheckmark: false,
                                            labelStyle: Theme.of(context)
                                                .textTheme
                                                .labelLarge,
                                            avatar: Icon(item.$3, size: 18),
                                            selected: _modes.contains(item.$1),
                                            onSelected: _busy
                                                ? null
                                                : (selected) => _change(() {
                                                      if (selected) {
                                                        _modes.add(item.$1);
                                                      } else {
                                                        _modes.remove(item.$1);
                                                      }
                                                    })),
                                    ]),
                                    const SizedBox(height: 16),
                                    DropdownButtonFormField<int>(
                                      initialValue: _maxWalkMinutes,
                                      isDense: false,
                                      decoration: const InputDecoration(
                                          labelText: 'Maks. dojście pieszo'),
                                      items: [
                                        for (final minutes in [10, 15, 30])
                                          DropdownMenuItem(
                                              value: minutes,
                                              child: Text('$minutes min'))
                                      ],
                                      onChanged: _busy
                                          ? null
                                          : (value) {
                                              if (value != null) {
                                                _change(() =>
                                                    _maxWalkMinutes = value);
                                              }
                                            },
                                    ),
                                    const SizedBox(height: 12),
                                  ]),
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                  onPressed: _busy ? null : () => _search(),
                                  icon: const Icon(Icons.search),
                                  label: const Text('Szukaj połączeń')),
                              if (_busy)
                                const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 16),
                                    child: LinearProgressIndicator()),
                              if (_error != null)
                                Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16),
                                    child: Text(_error!,
                                        style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .error))),
                              if (_results != null) ...[
                                const SizedBox(height: 20),
                                Text('Połączenia · ${_day(_query!.time)}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium),
                                const SizedBox(height: 12),
                                if (_results!.journeys.isEmpty)
                                  const Padding(
                                      padding:
                                          EdgeInsets.symmetric(vertical: 16),
                                      child: Text(
                                          'Brak połączeń dla wybranej trasy i terminu. Zmień godzinę lub środki transportu.')),
                                for (final journey in _results!.journeys)
                                  Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 10),
                                      child: _JourneyTile(
                                          journey: journey,
                                          origin: _query!.origin.name,
                                          destination:
                                              _query!.destination.name)),
                                Wrap(spacing: 8, runSpacing: 8, children: [
                                  if (_results!.previousCursor != null)
                                    OutlinedButton.icon(
                                        onPressed: _busy
                                            ? null
                                            : () => _search(
                                                cursor:
                                                    _results!.previousCursor),
                                        icon: const Icon(Icons.arrow_back),
                                        label: const Text('Wcześniejsze')),
                                  if (_results!.nextCursor != null)
                                    OutlinedButton.icon(
                                        onPressed: _busy
                                            ? null
                                            : () => _search(
                                                cursor: _results!.nextCursor),
                                        icon: const Icon(Icons.arrow_forward),
                                        label: const Text('Późniejsze')),
                                ]),
                              ],
                              const SizedBox(height: 24),
                              const Divider(),
                              const _TransitSources(),
                            ]))),
              ],
            ))),
      );
}

class _JourneyTile extends StatelessWidget {
  const _JourneyTile(
      {required this.journey, required this.origin, required this.destination});
  final TransitJourney journey;
  final String origin, destination;
  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => _JourneyDetails(
                  journey: journey, origin: origin, destination: destination))),
          child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                        spacing: 16,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                              '${_clock(journey.start)} – ${_clock(journey.end)}',
                              style: Theme.of(context).textTheme.titleMedium),
                          Text(travelDuration(journey.duration)),
                        ]),
                    Text(_day(journey.start)),
                    if (!DateUtils.isSameDay(journey.start, journey.end))
                      Text('Przyjazd ${_day(journey.end)}'),
                    const SizedBox(height: 8),
                    Wrap(spacing: 12, runSpacing: 8, children: [
                      for (final leg in journey.legs)
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(_modeIcon(leg), size: 18),
                          const SizedBox(width: 4),
                          Flexible(
                              child: Text(leg.walking
                                  ? travelDuration(leg.duration)
                                  : leg.line.isEmpty
                                      ? leg.label
                                      : leg.line))
                        ])
                    ]),
                    const SizedBox(height: 8),
                    Text(journey.transfers == 0
                        ? 'Bez przesiadek'
                        : 'Przesiadki: ${journey.transfers}'),
                    if (journey.cancelled)
                      Text('Połączenie odwołane',
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                    if (journey.legs.any((leg) => leg.extended))
                      const Text(
                          'Rozkład orientacyjny – termin poza opublikowanym rozkładem'),
                    const Align(
                        alignment: Alignment.centerRight,
                        child: Icon(Icons.chevron_right, size: 20)),
                  ])),
        ),
      );
}

class _JourneyDetails extends StatelessWidget {
  const _JourneyDetails(
      {required this.journey, required this.origin, required this.destination});
  final TransitJourney journey;
  final String origin, destination;
  String _name(Map<String, dynamic> place) => switch (place['name']) {
        'START' => origin,
        'END' => destination,
        final String _ => transitStopName(place),
        _ => 'Przystanek',
      };
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Szczegóły połączenia')),
        body: SafeArea(
            top: false,
            child: AppScrollView(
                child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(_day(journey.start),
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                Text('$origin → $destination',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('${_clock(journey.start)} – ${_clock(journey.end)}',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      Text(travelDuration(journey.duration),
                          style: Theme.of(context).textTheme.titleMedium),
                    ]),
                const SizedBox(height: 8),
                Wrap(spacing: 16, runSpacing: 6, children: [
                  Text(journey.transfers == 0
                      ? 'Bez przesiadek'
                      : 'Przesiadki: ${journey.transfers}'),
                  if (journey.legs.any((leg) => leg.walking))
                    Text(
                        'Pieszo ${travelDuration(journey.legs.where((leg) => leg.walking).fold(Duration.zero, (total, leg) => total + leg.duration))}'),
                ]),
                if (!DateUtils.isSameDay(journey.start, journey.end))
                  Text('Przyjazd ${_day(journey.end)}'),
                const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Divider()),
                for (var index = 0; index < journey.legs.length; index++) ...[
                  if (index > 0 &&
                      journey.legs[index].start
                          .isAfter(journey.legs[index - 1].end))
                    Padding(
                        padding: const EdgeInsets.only(left: 36, bottom: 16),
                        child: Text(
                            'Oczekiwanie · ${travelDuration(journey.legs[index].start.difference(journey.legs[index - 1].end))}',
                            style: Theme.of(context).textTheme.bodySmall)),
                  _JourneyLegSection(
                      leg: journey.legs[index],
                      name: _name,
                      last: index == journey.legs.length - 1),
                ],
                const _TransitSources(),
              ],
            ))),
      );
}

class _JourneyLegSection extends StatelessWidget {
  const _JourneyLegSection(
      {required this.leg, required this.name, required this.last});
  final TransitLeg leg;
  final String Function(Map<String, dynamic>) name;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final color = leg.cancelled
        ? colors.error
        : leg.walking
            ? colors.onSurfaceVariant
            : leg.mode == 'TRAM'
                ? colors.tertiary
                : (leg.mode == 'BUS' || leg.mode == 'COACH')
                    ? colors.primary
                    : colors.secondary;
    final delay = leg.start.difference(leg.scheduledStart).inMinutes;
    return Stack(children: [
      Container(
          margin: const EdgeInsets.only(left: 12),
          decoration: BoxDecoration(
              border: Border(
                  left: BorderSide(
                      color: last ? Colors.transparent : colors.outlineVariant,
                      width: 2))),
          padding: const EdgeInsets.only(left: 22, bottom: 24),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (leg.walking) ...[
              Wrap(spacing: 12, runSpacing: 4, children: [
                Text('Pieszo', style: theme.textTheme.titleMedium),
                Text(
                    '${travelDuration(leg.duration)}${leg.distance == null ? '' : ' · ${leg.distance} m'}',
                    style: theme.textTheme.bodyMedium),
              ]),
              const SizedBox(height: 4),
              Text(
                  name(leg.from) == name(leg.to)
                      ? name(leg.from)
                      : '${name(leg.from)} → ${name(leg.to)}',
                  style: theme.textTheme.bodySmall),
              const SizedBox(height: 4),
              Text('${_clock(leg.start)} – ${_clock(leg.end)}',
                  style: theme.textTheme.bodySmall),
            ] else ...[
              Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                            color: color.withValues(alpha: .14),
                            borderRadius: BorderRadius.circular(6)),
                        child: Text(leg.line.isEmpty ? leg.label : leg.line,
                            style: theme.textTheme.titleMedium?.copyWith(
                                color: color, fontWeight: FontWeight.w700))),
                    Text('${leg.label} · ${travelDuration(leg.duration)}',
                        style: theme.textTheme.bodySmall),
                  ]),
              if (leg.headsign.isNotEmpty)
                Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('Kierunek: ${leg.headsign}',
                        style: theme.textTheme.bodyMedium)),
              if (leg.staySeated)
                const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text('Pozostań w pojeździe')),
              if (leg.cancelled)
                Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('Kurs odwołany',
                        style: TextStyle(
                            color: colors.error, fontWeight: FontWeight.w700))),
              const SizedBox(height: 14),
              _JourneyStopRow(
                  time: leg.start,
                  scheduledTime: leg.realtime ? leg.scheduledStart : null,
                  title: name(leg.from),
                  detail: _platform(leg.from),
                  strong: true),
              if (leg.stops.isNotEmpty)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  shape: const Border(),
                  collapsedShape: const Border(),
                  title: Text('Przystanki po drodze (${leg.stops.length})',
                      style: theme.textTheme.bodySmall),
                  children: [
                    for (final stop in leg.stops)
                      _JourneyStopRow(
                          time: transitStopTime(stop),
                          scheduledTime: leg.realtime
                              ? transitStopTime(stop, scheduled: true)
                              : null,
                          title: name(stop))
                  ],
                )
              else
                const SizedBox(height: 12),
              _JourneyStopRow(
                  time: leg.end,
                  scheduledTime: leg.realtime ? leg.scheduledEnd : null,
                  title: name(leg.to),
                  detail: _platform(leg.to),
                  strong: true),
              const SizedBox(height: 10),
              Wrap(spacing: 10, runSpacing: 4, children: [
                Text(
                    leg.realtime
                        ? 'Na żywo${delay > 0 ? ' · +$delay min' : ''}'
                        : 'Według rozkładu',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: leg.realtime ? color : null)),
              ]),
              if (leg.agency.isNotEmpty)
                Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(leg.agency, style: theme.textTheme.bodySmall)),
            ],
            if (!DateUtils.isSameDay(leg.start, leg.end))
              Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Przyjazd ${_day(leg.end)}')),
            if (leg.extended)
              Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                      'Rozkład orientacyjny. Termin poza opublikowanym rozkładem.',
                      style: TextStyle(color: colors.error))),
          ])),
      Positioned(
          left: 0,
          top: 2,
          child: ColoredBox(
              color: theme.scaffoldBackgroundColor,
              child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Icon(_modeIcon(leg), size: 26, color: color)))),
    ]);
  }

  String? _platform(Map<String, dynamic> stop) {
    final track = stop['track'] ?? stop['scheduledTrack'];
    if (track is! String || track.isEmpty) return null;
    return '${leg.label == 'Pociąg' ? 'Peron / tor' : 'Stanowisko'}: $track';
  }
}

class _JourneyStopRow extends StatelessWidget {
  const _JourneyStopRow(
      {required this.time,
      required this.title,
      this.scheduledTime,
      this.detail,
      this.strong = false});
  final DateTime? time;
  final DateTime? scheduledTime;
  final String title;
  final String? detail;
  final bool strong;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final changed = time != null &&
        scheduledTime != null &&
        !time!.isAtSameMomentAs(scheduledTime!) &&
        _clock(time!) != _clock(scheduledTime!);
    final timeWidth =
        MediaQuery.textScalerOf(context).scale(14) * (changed ? 7.5 : 3.5) + 8;
    final times = Wrap(spacing: 8, runSpacing: 2, children: [
      if (changed)
        Text(_clock(scheduledTime!),
            style: theme.textTheme.bodyMedium?.copyWith(
                decoration: TextDecoration.lineThrough,
                color: theme.colorScheme.onSurfaceVariant)),
      Text(time == null ? '·' : _clock(time!),
          style: theme.textTheme.bodyMedium?.copyWith(
              color: changed ? theme.colorScheme.primary : null,
              fontWeight: strong || changed ? FontWeight.w700 : null)),
    ]);
    final stop =
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title,
          style: theme.textTheme.bodyMedium
              ?.copyWith(fontWeight: strong ? FontWeight.w600 : null)),
      if (detail != null) Text(detail!, style: theme.textTheme.bodySmall),
    ]);
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: LayoutBuilder(builder: (context, constraints) {
          if (changed && timeWidth > constraints.maxWidth * .5) {
            return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [times, const SizedBox(height: 4), stop]);
          }
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: timeWidth, child: times),
            Expanded(child: stop),
          ]);
        }));
  }
}

class _TransitSources extends StatelessWidget {
  const _TransitSources();
  Future<void> _open(BuildContext context, String url) async {
    try {
      if (await launchUrl(Uri.parse(url),
          mode: LaunchMode.externalApplication)) {
        return;
      }
    } catch (_) {/* A missing browser must not break the planner. */}
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Nie udało się otworzyć strony źródłowej.')));
    }
  }

  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, children: [
        TextButton(
            onPressed: () => _open(context, 'https://transitous.org/sources/'),
            child: const Text('Dane: Transitous i dostawcy')),
        TextButton(
            onPressed: () =>
                _open(context, 'https://www.openstreetmap.org/copyright'),
            child: const Text('© OpenStreetMap contributors')),
      ]);
}
