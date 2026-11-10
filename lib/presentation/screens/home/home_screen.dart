// lib/presentation/screens/home/home_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../providers/providers.dart';
import '../../widgets/class_card.dart';
import '../../widgets/failure_view.dart';
import '../../widgets/app_scroll_view.dart';
import '../../widgets/event_editor_sheet.dart';
import '../../widgets/schedule_entry_details_sheet.dart';
import '../search/search_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  double _dayDrag = 0;

  void _finishDaySwipe(DragEndDetails details) {
    final distance = _dayDrag;
    _dayDrag = 0;
    final threshold =
        (MediaQuery.sizeOf(context).width * 0.2).clamp(56.0, 100.0);
    final velocity = details.primaryVelocity ?? 0;
    final longSwipe = distance.abs() >= threshold;
    final flick = distance.abs() >= 24 && velocity.abs() >= 500;
    if (!longSwipe && !flick) return;
    final direction = longSwipe ? distance : velocity;
    final currentDate = ref.read(selectedDateProvider);
    _setSelectedDate(ref, _moveDateByDays(currentDate, direction < 0 ? 1 : -1));
  }

  @override
  Widget build(BuildContext context) {
    final selectedDate = ref.watch(selectedDateProvider);
    final schedule = ref.watch(todayScheduleProvider);
    final isRefreshing = ref.watch(isRefreshingProvider);
    final refreshInfo = ref.watch(refreshInfoProvider);
    final lastRefreshText = _formatLastRefresh(refreshInfo);
    final classTypeColors = ref.watch(classTypeColorsProvider).value ?? {};

    return Scaffold(
      appBar: AppBar(
        title: Text(_isToday(selectedDate) ? 'Dzisiaj' : 'Plan dnia'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded),
            tooltip: 'Wyszukaj',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SearchScreen()),
            ),
          ),
          if (isRefreshing)
            Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primary,
                ),
              ),
            )
          else
            IconButton(
              icon: Icon(Icons.refresh_rounded),
              onPressed: () => _refresh(ref, context),
              tooltip: 'Odśwież plan',
            ),
          IconButton(
            icon: Icon(Icons.add_circle_outline_rounded),
            onPressed: () => _addEvent(context, ref, selectedDate),
            tooltip: 'Dodaj wydarzenie',
          ),
        ],
      ),
      body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (_) => _dayDrag = 0,
          onHorizontalDragUpdate: (details) =>
              _dayDrag += details.primaryDelta ?? 0,
          onHorizontalDragEnd: _finishDaySwipe,
          onHorizontalDragCancel: () => _dayDrag = 0,
          child: AppScrollView(
              key: ValueKey(selectedDate),
              child: RefreshIndicator(
                color: AppColors.primary,
                backgroundColor: AppColors.surface,
                onRefresh: () => _refresh(ref, context),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(top: 8, bottom: 32),
                  children: [
                    Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Text(lastRefreshText,
                            style: TextStyle(
                                color: AppColors.onSurfaceMuted,
                                fontSize: 11))),
                    _DateNavigator(
                      date: selectedDate,
                      onPrevious: () => _setSelectedDate(
                        ref,
                        _moveDateByDays(selectedDate, -1),
                      ),
                      onPick: () => _pickDate(context, ref, selectedDate),
                      onToday: () => _setSelectedDate(ref, DateTime.now()),
                      onNext: () => _setSelectedDate(
                        ref,
                        _moveDateByDays(selectedDate, 1),
                      ),
                    ),
                    if (refreshInfo.valueOrNull?.hasFailure == true)
                      _OfflineNotice(
                        info: refreshInfo.valueOrNull!,
                        hasEntries: schedule.valueOrNull?.isNotEmpty == true,
                      ),
                    ...schedule.when<List<Widget>>(
                      loading: () => [
                        SizedBox(
                            height: 180,
                            child: Center(
                              child: CircularProgressIndicator(
                                  color: AppColors.primary),
                            ))
                      ],
                      error: (err, _) => [
                        FailureView(
                            error: err,
                            onRetry: () =>
                                ref.invalidate(todayScheduleProvider))
                      ],
                      data: (entries) {
                        if (entries.isEmpty) {
                          return [
                            Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 32),
                                child: _EmptyDay(date: selectedDate))
                          ];
                        }
                        return buildScheduleWidgets(
                          entries,
                          classTypeColors: classTypeColors,
                          onEntryTap: (entry) => showScheduleEntryDetailsSheet(
                            context: context,
                            entry: entry,
                            onLecturerTap: entry.lecturer.isEmpty
                                ? null
                                : () => openLecturer(context, entry.lecturer),
                            onRoomTap: entry.room.isEmpty
                                ? null
                                : () => openRoom(context, entry.room),
                            onEdit: entry.groupId == 'user'
                                ? () => showUserEventSheetForEntry(
                                      context: context,
                                      ref: ref,
                                      entry: entry,
                                    )
                                : null,
                          ),
                          onEntryLongPress: (entry) =>
                              showUserEventSheetForEntry(
                            context: context,
                            ref: ref,
                            entry: entry,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ))),
    );
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  void _setSelectedDate(WidgetRef ref, DateTime date) {
    ref.read(selectedDateProvider.notifier).state =
        DateTime(date.year, date.month, date.day);
  }

  DateTime _moveDateByDays(DateTime date, int days) {
    return DateTime(date.year, date.month, date.day + days);
  }

  Future<void> _pickDate(
    BuildContext context,
    WidgetRef ref,
    DateTime currentDate,
  ) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: currentDate,
      firstDate:
          DateTime(currentDate.year - 5, currentDate.month, currentDate.day),
      lastDate:
          DateTime(currentDate.year + 5, currentDate.month, currentDate.day),
    );
    if (picked != null) {
      _setSelectedDate(ref, picked);
    }
  }

  String _formatLastRefresh(AsyncValue<RefreshInfo> refreshInfo) {
    return refreshInfo.maybeWhen(
      data: (info) {
        final lastRefreshAt = info.lastRefreshAt;
        if (lastRefreshAt == null) {
          return 'Ostatnia aktualizacja: brak';
        }
        return 'Ostatnia aktualizacja: ${DateFormat('dd.MM.yyyy HH:mm').format(lastRefreshAt)}';
      },
      loading: () => 'Ostatnia aktualizacja: ...',
      orElse: () => 'Ostatnia aktualizacja: brak',
    );
  }

  Future<void> _refresh(WidgetRef ref, BuildContext context) async {
    if (ref.read(isRefreshingProvider)) return;
    final refreshing = ref.read(isRefreshingProvider.notifier);
    final repository = ref.read(scheduleRepositoryProvider);
    refreshing.state = true;
    try {
      final result = await repository.refreshAllGroups();
      if (!context.mounted) return;
      ref.invalidate(todayScheduleProvider);
      ref.invalidate(refreshInfoProvider);
      if (!result.isSuccessful) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Nie udało się odświeżyć całego planu. Zapisane zajęcia pozostają dostępne.'),
          ),
        );
      } else if (result.changed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Plan zajęć się zmienił!'),
            backgroundColor: AppColors.warning,
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (_) {
      if (!context.mounted) return;
      ref.invalidate(refreshInfoProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Nie udało się odświeżyć planu. Spróbuj ponownie później.'),
          ),
        );
      }
    } finally {
      if (refreshing.mounted) refreshing.state = false;
    }
  }

  void _addEvent(BuildContext context, WidgetRef ref, DateTime selectedDate) {
    showUserEventSheet(
      context: context,
      ref: ref,
      initialDate: selectedDate,
    );
  }
}

class _OfflineNotice extends StatelessWidget {
  const _OfflineNotice({required this.info, required this.hasEntries});

  final RefreshInfo info;
  final bool hasEntries;

  @override
  Widget build(BuildContext context) {
    final last = info.lastRefreshAt;
    final retry = info.nextRetryAt;
    final message = info.status == 'partial_changed'
        ? 'Nie udało się odświeżyć części grup. Niektóre zajęcia mogą być nieaktualne.'
        : 'Nie udało się odświeżyć planu z serwera UEK.';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.cloud_off_rounded, size: 20, color: AppColors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              [
                message,
                if (last != null)
                  'Ostatnia pełna aktualizacja: ${DateFormat('dd.MM.yyyy HH:mm').format(last)}.'
                else if (hasEntries)
                  'Wyświetlam zapisane zajęcia.'
                else
                  'Jeśli plan nie był wcześniej pobrany, zajęcia pojawią się po przywróceniu połączenia.',
                if (retry != null)
                  'Kolejna automatyczna próba najwcześniej o ${DateFormat('HH:mm').format(retry)}.',
              ].join('\n'),
              style: TextStyle(color: AppColors.onSurfaceMuted, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _DateNavigator extends StatelessWidget {
  final DateTime date;
  final VoidCallback onPrevious;
  final VoidCallback onPick;
  final VoidCallback onToday;
  final VoidCallback onNext;

  _DateNavigator({
    required this.date,
    required this.onPrevious,
    required this.onPick,
    required this.onToday,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.chevron_left_rounded),
            onPressed: onPrevious,
            tooltip: 'Poprzedni dzien',
          ),
          Expanded(
            child: LayoutBuilder(builder: (context, constraints) {
              final dateLabel =
                  '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
              final fullLabel = '$dateLabel · ${_weekdayName(date)}';
              final style = Theme.of(context).textTheme.labelLarge!;
              final painter = TextPainter(
                  text: TextSpan(text: fullLabel, style: style),
                  textScaler: MediaQuery.textScalerOf(context),
                  textDirection: Directionality.of(context))
                ..layout();
              final fits = painter.width <= constraints.maxWidth - 16;
              painter.dispose();
              const shortDays = [
                'pon.',
                'wt.',
                'śr.',
                'czw.',
                'pt.',
                'sob.',
                'niedz.'
              ];
              return Tooltip(
                  message: fullLabel,
                  child: TextButton(
                    onPressed: onPick,
                    style: TextButton.styleFrom(
                      textStyle: style,
                      foregroundColor: AppColors.onSurface,
                      backgroundColor: AppColors.surfaceVariant,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 12),
                    ),
                    child: Text(
                        fits
                            ? fullLabel
                            : '$dateLabel · ${shortDays[date.weekday - 1]}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        semanticsLabel: fullLabel),
                  ));
            }),
          ),
          IconButton(
            icon: Icon(Icons.today_rounded),
            onPressed: onToday,
            tooltip: 'Dzisiaj',
          ),
          IconButton(
            icon: Icon(Icons.chevron_right_rounded),
            onPressed: onNext,
            tooltip: 'Nastepny dzien',
          ),
        ],
      ),
    );
  }

  String _weekdayName(DateTime date) {
    const weekdays = [
      'poniedziałek',
      'wtorek',
      'środa',
      'czwartek',
      'piątek',
      'sobota',
      'niedziela',
    ];
    return weekdays[date.weekday - 1];
  }
}

class _EmptyDay extends StatelessWidget {
  final DateTime date;
  _EmptyDay({required this.date});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(
              Icons.event_available_rounded,
              color: AppColors.onSurfaceMuted,
              size: 40,
            ),
          ),
          SizedBox(height: 16),
          Text(
            'Brak zajec dzisiaj',
            style: TextStyle(
              color: AppColors.onSurface,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Milego dnia wolnego!',
            style: TextStyle(color: AppColors.onSurfaceMuted, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
