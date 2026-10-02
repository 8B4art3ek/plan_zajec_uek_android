// lib/presentation/screens/home/home_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../providers/providers.dart';
import '../../widgets/class_card.dart';
import '../../widgets/event_editor_sheet.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedDate = ref.watch(selectedDateProvider);
    final dateStr = _formatPolishDate(selectedDate);
    final schedule = ref.watch(todayScheduleProvider);
    final isRefreshing = ref.watch(isRefreshingProvider);
    final refreshInfo = ref.watch(refreshInfoProvider);
    final lastRefreshText = _formatLastRefresh(refreshInfo);
    final classTypeColors =
        ref.watch(classTypeColorsProvider).value ?? const {};

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 78,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_isToday(selectedDate) ? 'Dzisiaj' : 'Plan dnia'),
            Text(
              dateStr,
              style: const TextStyle(
                color: AppColors.onSurfaceMuted,
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              lastRefreshText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.onSurfaceMuted,
                fontSize: 11,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
        actions: [
          if (isRefreshing)
            const Padding(
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
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () => _refresh(ref, context),
              tooltip: 'Odswierz plan',
            ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded),
            onPressed: () => _addEvent(context, ref, selectedDate),
            tooltip: 'Dodaj wydarzenie',
          ),
        ],
      ),
      body: Column(
        children: [
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
          Expanded(
            child: schedule.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
              error: (err, _) => _ErrorWidget(error: err.toString()),
              data: (entries) {
                if (entries.isEmpty) {
                  return _EmptyDay(date: selectedDate);
                }
                return RefreshIndicator(
                  color: AppColors.primary,
                  backgroundColor: AppColors.surface,
                  onRefresh: () => _refresh(ref, context),
                  child: ListView(
                    padding: const EdgeInsets.only(top: 8, bottom: 32),
                    children: buildScheduleWidgets(
                      entries,
                      classTypeColors: classTypeColors,
                      onEntryTap: (entry) => showUserEventSheetForEntry(
                        context: context,
                        ref: ref,
                        entry: entry,
                      ),
                      onEntryLongPress: (entry) => showUserEventSheetForEntry(
                        context: context,
                        ref: ref,
                        entry: entry,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
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

  String _formatPolishDate(DateTime date) {
    const days = [
      'Poniedzialek',
      'Wtorek',
      'Sroda',
      'Czwartek',
      'Piatek',
      'Sobota',
      'Niedziela'
    ];
    const months = [
      '',
      'stycznia',
      'lutego',
      'marca',
      'kwietnia',
      'maja',
      'czerwca',
      'lipca',
      'sierpnia',
      'wrzesnia',
      'pazdziernika',
      'listopada',
      'grudnia'
    ];
    final day = days[date.weekday - 1];
    final month = months[date.month];
    return '$day, ${date.day} $month ${date.year}';
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
    ref.read(isRefreshingProvider.notifier).state = true;
    try {
      final changed =
          await ref.read(scheduleRepositoryProvider).refreshAllGroups();
      ref.invalidate(todayScheduleProvider);
      ref.invalidate(refreshInfoProvider);
      if (changed && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Plan zajec sie zmienil!'),
            backgroundColor: AppColors.warning,
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      await ref.read(scheduleRepositoryProvider).recordRefreshFailure(e);
      ref.invalidate(refreshInfoProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Blad: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      ref.read(isRefreshingProvider.notifier).state = false;
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

class _DateNavigator extends StatelessWidget {
  final DateTime date;
  final VoidCallback onPrevious;
  final VoidCallback onPick;
  final VoidCallback onToday;
  final VoidCallback onNext;

  const _DateNavigator({
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
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: onPrevious,
            tooltip: 'Poprzedni dzien',
          ),
          Expanded(
            child: TextButton.icon(
              onPressed: onPick,
              icon: const Icon(Icons.calendar_month_rounded, size: 18),
              label: Text(
                '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year} (${_weekdayName(date)})',
                overflow: TextOverflow.ellipsis,
              ),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.onSurface,
                backgroundColor: AppColors.surfaceVariant,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.today_rounded),
            onPressed: onToday,
            tooltip: 'Dzisiaj',
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: onNext,
            tooltip: 'Nastepny dzien',
          ),
        ],
      ),
    );
  }

  String _weekdayName(DateTime date) {
    const weekdays = [
      'poniedzialek',
      'wtorek',
      'sroda',
      'czwartek',
      'piatek',
      'sobota',
      'niedziela',
    ];
    return weekdays[date.weekday - 1];
  }
}

class _EmptyDay extends StatelessWidget {
  final DateTime date;
  const _EmptyDay({required this.date});

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
            child: const Icon(
              Icons.event_available_rounded,
              color: AppColors.onSurfaceMuted,
              size: 40,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Brak zajec dzisiaj',
            style: TextStyle(
              color: AppColors.onSurface,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Milego dnia wolnego!',
            style: TextStyle(color: AppColors.onSurfaceMuted, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _ErrorWidget extends StatelessWidget {
  final String error;
  const _ErrorWidget({required this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: AppColors.error, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Cos poszlo nie tak',
              style: TextStyle(
                color: AppColors.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: const TextStyle(
                  color: AppColors.onSurfaceMuted, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
