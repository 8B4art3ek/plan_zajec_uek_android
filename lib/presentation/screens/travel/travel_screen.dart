import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/date_labels.dart';
import '../../../domain/entities/campus_trip.dart';
import '../../providers/providers.dart';
import '../../widgets/app_scroll_view.dart';

final tripLauncherProvider = Provider<Future<bool> Function(Uri)>(
    (ref) => (uri) => launchUrl(uri, mode: LaunchMode.externalApplication));

class TravelScreen extends StatelessWidget {
  const TravelScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Dojazdy')),
        body: const Center(child: Text('Wkrótce')),
      );
}

// Retain the planner for later, without exposing it through app navigation.
class TravelPlannerScreen extends ConsumerStatefulWidget {
  const TravelPlannerScreen({super.key});
  @override
  ConsumerState<TravelPlannerScreen> createState() => _TravelScreenState();
}

class _TravelScreenState extends ConsumerState<TravelPlannerScreen> {
  final _origin = TextEditingController();
  final _form = GlobalKey<FormState>();
  CampusDestination _destination = CampusDestination.campus;
  DateTime _date = DateTime.now();
  TimeOfDay _time = TimeOfDay.now();
  bool _arriveBy = false;
  final _transport = TripTransport.values.toSet();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _origin.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (_busy || !_form.currentState!.validate()) return;
    if (_transport.isEmpty) {
      setState(() => _error = 'Wybierz przynajmniej jeden środek transportu.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final uri = campusTripLink(
          origin: _origin.text,
          destination: _destination,
          dateTime: DateTime(
              _date.year, _date.month, _date.day, _time.hour, _time.minute),
          arriveBy: _arriveBy,
          transport: _transport);
      if (!await ref.read(tripLauncherProvider)(uri)) {
        throw StateError('No URL handler');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Nie udało się otworzyć Jakdojade. Sprawdź, czy masz przeglądarkę, i spróbuj ponownie.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _firstClass() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final selected = ref.read(selectedDateProvider);
      final entries = await ref
          .read(scheduleRepositoryProvider)
          .getEntriesForDate(selected);
      final starts = <DateTime>[];
      for (final entry
          in entries.where((entry) => !entry.isMoved && !entry.isReservation)) {
        final parts = entry.startTime.split(':');
        if (parts.length != 2) continue;
        final hour = int.tryParse(parts[0]);
        final minute = int.tryParse(parts[1]);
        if (hour != null &&
            minute != null &&
            hour >= 0 &&
            hour <= 23 &&
            minute >= 0 &&
            minute <= 59) {
          starts.add(DateTime(
              entry.date.year, entry.date.month, entry.date.day, hour, minute));
        }
      }
      starts.sort();
      if (!mounted) return;
      if (starts.isEmpty) {
        setState(() => _error = 'Brak zajęć w wybranym dniu planu.');
        return;
      }
      final arrival = starts.first.subtract(const Duration(minutes: 10));
      if (arrival.isBefore(DateTime.now())) {
        setState(() => _error =
            'Pierwsze zajęcia w tym dniu już się rozpoczęły lub nie ma czasu na dojazd. Wybierz późniejszy dzień w planie.');
        return;
      }
      setState(() {
        _date = arrival;
        _time = TimeOfDay.fromDateTime(arrival);
        _arriveBy = true;
        _destination = CampusDestination.campus;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Nie udało się odczytać planu. Datę i godzinę możesz ustawić ręcznie.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Na uczelnię')),
        body: SafeArea(
            top: false,
            child: AppScrollView(
                child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                Form(
                    key: _form,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextFormField(
                            controller: _origin,
                            maxLength: 200,
                            textInputAction: TextInputAction.done,
                            decoration: const InputDecoration(
                                labelText: 'Skąd',
                                hintText: 'Adres, przystanek lub miejscowość',
                                prefixIcon: Icon(Icons.trip_origin),
                                counterText: ''),
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                    ? 'Wpisz początek podróży'
                                    : RegExp(r'[\x00-\x1F]').hasMatch(value)
                                        ? 'Wpisz adres w jednym wierszu'
                                        : null,
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<CampusDestination>(
                            initialValue: _destination,
                            key: ValueKey(_destination),
                            isExpanded: true,
                            itemHeight: null,
                            decoration: const InputDecoration(
                                labelText: 'Dokąd',
                                prefixIcon: Icon(Icons.place_outlined)),
                            items: [
                              for (final value in CampusDestination.values)
                                DropdownMenuItem(
                                    value: value,
                                    child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 8),
                                        child: Text(value.label)))
                            ],
                            onChanged: _busy
                                ? null
                                : (value) =>
                                    setState(() => _destination = value!),
                          ),
                          const SizedBox(height: 16),
                          SegmentedButton<bool>(
                            showSelectedIcon: false,
                            segments: const [
                              ButtonSegment(
                                  value: false, label: Text('Wyjazd')),
                              ButtonSegment(
                                  value: true, label: Text('Na miejscu'))
                            ],
                            selected: {_arriveBy},
                            onSelectionChanged: _busy
                                ? null
                                : (values) =>
                                    setState(() => _arriveBy = values.single),
                          ),
                          const SizedBox(height: 8),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.calendar_today_outlined),
                            title: Text(
                                '${DateFormat('dd.MM.yyyy').format(_date)} · ${polishWeekday(_date)}'),
                            trailing: const Icon(Icons.edit_outlined),
                            onTap: _busy
                                ? null
                                : () async {
                                    final now = DateTime.now();
                                    final day = await showDatePicker(
                                        context: context,
                                        initialDate: _date.isBefore(DateTime(
                                                now.year, now.month, now.day))
                                            ? now
                                            : _date,
                                        firstDate: DateTime(
                                            now.year, now.month, now.day),
                                        lastDate:
                                            DateTime(now.year + 2, 12, 31));
                                    if (day != null && mounted) {
                                      setState(() => _date = day);
                                    }
                                  },
                          ),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.schedule_outlined),
                            title: Text(_time.format(context)),
                            trailing: const Icon(Icons.edit_outlined),
                            onTap: _busy
                                ? null
                                : () async {
                                    final time = await showTimePicker(
                                        context: context, initialTime: _time);
                                    if (time != null && mounted) {
                                      setState(() => _time = time);
                                    }
                                  },
                          ),
                          TextButton.icon(
                              onPressed: _busy ? null : _firstClass,
                              icon: const Icon(Icons.event_available_outlined),
                              label: const Text(
                                  '10 min przed pierwszymi zajęciami')),
                          const SizedBox(height: 12),
                          Wrap(spacing: 8, runSpacing: 8, children: [
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
                                  avatar: Icon(item.$3, size: 18),
                                  selected: _transport.contains(item.$1),
                                  onSelected: _busy
                                      ? null
                                      : (selected) => setState(() {
                                            if (selected) {
                                              _transport.add(item.$1);
                                            } else {
                                              _transport.remove(item.$1);
                                            }
                                          })),
                          ]),
                          if (_error != null) ...[
                            const SizedBox(height: 16),
                            Text(_error!,
                                style: TextStyle(
                                    color: Theme.of(context).colorScheme.error))
                          ],
                          const SizedBox(height: 24),
                          FilledButton.icon(
                              onPressed: _busy ? null : _search,
                              icon: const Icon(Icons.open_in_new),
                              label: Text(_busy
                                  ? 'Otwieranie…'
                                  : 'Szukaj w Jakdojade')),
                        ]))
              ],
            ))),
      );
}
