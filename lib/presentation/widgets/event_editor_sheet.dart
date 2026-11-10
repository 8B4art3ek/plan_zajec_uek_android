import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/schedule_entry.dart';
import '../../domain/entities/user_event.dart';
import '../providers/providers.dart';

Future<void> showUserEventSheet({
  required BuildContext context,
  required WidgetRef ref,
  DateTime? initialDate,
  UserEvent? event,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => UserEventSheet(
      widgetRef: ref,
      initialDate: initialDate,
      event: event,
    ),
  );
}

Future<void> showUserEventSheetForEntry({
  required BuildContext context,
  required WidgetRef ref,
  required ScheduleEntry entry,
}) async {
  if (entry.groupId != 'user') return;

  final eventId = _eventIdFromEntry(entry);
  if (eventId == null) return;

  final events = await ref.read(userEventsProvider.future);
  if (!context.mounted) return;
  UserEvent? event;
  for (final candidate in events) {
    if (candidate.id == eventId) {
      event = candidate;
      break;
    }
  }

  if (event == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('To wydarzenie już nie istnieje.')),
    );
    return;
  }

  await showUserEventSheet(
    context: context,
    ref: ref,
    event: event,
  );
}

int? _eventIdFromEntry(ScheduleEntry entry) {
  const prefix = 'event_';
  if (!entry.id.startsWith(prefix)) return null;
  return int.tryParse(entry.id.substring(prefix.length));
}

class UserEventSheet extends StatefulWidget {
  final WidgetRef widgetRef;
  final DateTime? initialDate;
  final UserEvent? event;

  UserEventSheet({
    super.key,
    required this.widgetRef,
    this.initialDate,
    this.event,
  });

  @override
  State<UserEventSheet> createState() => _UserEventSheetState();
}

class _UserEventSheetState extends State<UserEventSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _typeCtrl = TextEditingController();
  final _roomCtrl = TextEditingController();
  late DateTime _selectedDate;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  bool _isSaving = false;
  String? _error;

  bool get _isEditing => widget.event?.id != null;

  @override
  void initState() {
    super.initState();
    final event = widget.event;
    _titleCtrl.text = event?.title ?? '';
    _typeCtrl.text = event?.eventType ?? UserEvent.defaultEventType;
    _roomCtrl.text = event?.room ?? '';
    _selectedDate = event?.date ?? widget.initialDate ?? DateTime.now();
    _startTime = _parseTime(event?.startTime) ?? TimeOfDay(hour: 9, minute: 0);
    _endTime = _parseTime(event?.endTime) ?? TimeOfDay(hour: 10, minute: 30);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _typeCtrl.dispose();
    _roomCtrl.dispose();
    super.dispose();
  }

  TimeOfDay? _parseTime(String? value) {
    if (value == null) return null;
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  int _minutes(TimeOfDay t) => t.hour * 60 + t.minute;

  Future<void> _save() async {
    if (_isSaving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_minutes(_endTime) <= _minutes(_startTime)) {
      setState(() => _error = 'Koniec musi być po początku.');
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });

    final event = UserEvent(
      id: widget.event?.id,
      title: _titleCtrl.text.trim(),
      eventType: _normalizedEventType,
      description: widget.event?.description,
      date: DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
      ),
      startTime: _fmt(_startTime),
      endTime: _fmt(_endTime),
      room: _roomCtrl.text.trim().isEmpty ? null : _roomCtrl.text.trim(),
    );

    try {
      final notifier = widget.widgetRef.read(userEventsProvider.notifier);
      if (_isEditing) {
        await notifier.updateUserEvent(event);
      } else {
        await notifier.add(event);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  String get _normalizedEventType {
    final value = _typeCtrl.text.trim();
    if (value.isEmpty) return UserEvent.defaultEventType;
    return value;
  }

  Future<void> _delete() async {
    final id = widget.event?.id;
    if (id == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'Usun wydarzenie',
          style: TextStyle(color: AppColors.onSurface),
        ),
        content: Text(
          'Czy na pewno chcesz usunac to wydarzenie?',
          style: TextStyle(color: AppColors.onSurfaceMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Anuluj',
              style: TextStyle(color: AppColors.onSurfaceMuted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Usun',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await widget.widgetRef.read(userEventsProvider.notifier).delete(id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.paddingOf(context).bottom +
            20,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                      child: Text(
                    _isEditing ? 'Edytuj wydarzenie' : 'Dodaj wydarzenie',
                    style: TextStyle(
                      color: AppColors.onSurface,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  )),
                  IconButton(
                    icon: Icon(
                      Icons.close,
                      color: AppColors.onSurfaceMuted,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              SizedBox(height: 16),
              TextFormField(
                controller: _titleCtrl,
                decoration: InputDecoration(labelText: 'Tytul'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Podaj tytul' : null,
              ),
              SizedBox(height: 12),
              TextFormField(
                controller: _typeCtrl,
                decoration: InputDecoration(
                  labelText: 'Typ wydarzenia',
                  hintText: 'np. Egzamin, zerowka, kolos',
                ),
              ),
              SizedBox(height: 12),
              TextFormField(
                controller: _roomCtrl,
                decoration: InputDecoration(labelText: 'Sala (opcjonalnie)'),
              ),
              SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate,
                    firstDate: DateTime.now().subtract(Duration(days: 365 * 5)),
                    lastDate: DateTime.now().add(Duration(days: 365 * 5)),
                  );
                  if (d != null) setState(() => _selectedDate = d);
                },
                child: InputDecorator(
                  decoration: InputDecoration(labelText: 'Data'),
                  child: Text(
                    DateFormat('dd.MM.yyyy').format(_selectedDate),
                    style: TextStyle(color: AppColors.onSurface),
                  ),
                ),
              ),
              SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final t = await showTimePicker(
                          context: context,
                          initialTime: _startTime,
                        );
                        if (t != null) setState(() => _startTime = t);
                      },
                      child: InputDecorator(
                        decoration: InputDecoration(labelText: 'Poczatek'),
                        child: Text(
                          _fmt(_startTime),
                          style: TextStyle(color: AppColors.onSurface),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final t = await showTimePicker(
                          context: context,
                          initialTime: _endTime,
                        );
                        if (t != null) setState(() => _endTime = t);
                      },
                      child: InputDecorator(
                        decoration: InputDecoration(labelText: 'Koniec'),
                        child: Text(
                          _fmt(_endTime),
                          style: TextStyle(color: AppColors.onSurface),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (_error != null) ...[
                SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: AppColors.error, fontSize: 13),
                ),
              ],
              SizedBox(height: 20),
              OverflowBar(
                alignment: MainAxisAlignment.end,
                spacing: 12,
                overflowSpacing: 8,
                children: [
                  if (_isEditing)
                    TextButton.icon(
                      onPressed: _isSaving ? null : _delete,
                      icon: Icon(Icons.delete_outline_rounded, size: 18),
                      label: Text('Usun'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.error,
                      ),
                    ),
                  ElevatedButton(
                    onPressed: _isSaving ? null : _save,
                    child: _isSaving
                        ? SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Theme.of(context).colorScheme.onPrimary,
                            ),
                          )
                        : Text(_isEditing ? 'Zapisz zmiany' : 'Zapisz'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
