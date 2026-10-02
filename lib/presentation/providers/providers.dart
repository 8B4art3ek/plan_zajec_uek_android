// lib/presentation/providers/providers.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../data/datasources/auth_service.dart';
import '../../data/datasources/local_database.dart';
import '../../data/datasources/schedule_parser.dart';
import '../../data/datasources/schedule_remote_datasource.dart';
import '../../data/repositories/schedule_repository_impl.dart';
import '../../domain/entities/group.dart';
import '../../domain/entities/schedule_entry.dart';
import '../../domain/entities/subject_filter.dart';
import '../../domain/entities/user_event.dart';

// ---- Infrastructure Providers ----

final localDatabaseProvider = Provider<LocalDatabase>((ref) {
  final db = LocalDatabase();
  ref.onDispose(() => db.close());
  return db;
});

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final remoteDatasourceProvider =
    Provider<ScheduleRemoteDatasource>((ref) => ScheduleRemoteDatasource());

final scheduleParserProvider =
    Provider<ScheduleParser>((ref) => ScheduleParser());

final scheduleRepositoryProvider = Provider<ScheduleRepository>((ref) {
  return ScheduleRepository(
    db: ref.watch(localDatabaseProvider),
    remote: ref.watch(remoteDatasourceProvider),
    parser: ref.watch(scheduleParserProvider),
    auth: ref.watch(authServiceProvider),
  );
});

// ---- Auth Providers ----

final credentialsProvider = FutureProvider<Credentials?>((ref) {
  return ref.watch(authServiceProvider).getCredentials();
});

final isLoggedInProvider = FutureProvider<bool>((ref) async {
  final creds = await ref.watch(credentialsProvider.future);
  return creds != null;
});

// ---- Groups Provider ----

final groupsProvider =
    AsyncNotifierProvider<GroupsNotifier, List<Group>>(GroupsNotifier.new);

class GroupsNotifier extends AsyncNotifier<List<Group>> {
  @override
  Future<List<Group>> build() async {
    return ref.watch(scheduleRepositoryProvider).getGroups();
  }

  Future<void> addGroup(Group group) async {
    await ref.read(scheduleRepositoryProvider).addGroup(group);
    ref.invalidateSelf();
  }

  Future<void> updateGroup(Group group) async {
    await ref.read(scheduleRepositoryProvider).updateGroup(group);
    ref.invalidateSelf();
  }

  Future<void> deleteGroup(String groupId) async {
    await ref.read(scheduleRepositoryProvider).deleteGroup(groupId);
    ref.invalidateSelf();
  }
}

// ---- Today's schedule ----

final selectedDateProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});

final todayScheduleProvider =
    FutureProvider.autoDispose<List<ScheduleEntry>>((ref) async {
  final repo = ref.watch(scheduleRepositoryProvider);
  final selectedDate = ref.watch(selectedDateProvider);
  final date = DateTime(
    selectedDate.year,
    selectedDate.month,
    selectedDate.day,
  );
  final entries = await repo.getEntriesForDate(date);
  final events = await repo.getUserEvents();
  final hideRes = await repo.getHideReservations();

  // Convert user events to schedule entries for display
  final eventEntries = events
      .where((e) => _sameDay(e.date, date))
      .map((e) => ScheduleEntry(
            id: 'event_${e.id}',
            subject: e.title,
            classType: e.eventType,
            lecturer: '',
            room: e.room ?? '',
            date: e.date,
            startTime: e.startTime,
            endTime: e.endTime,
            weekday: '',
            durationHours: 0,
            groupId: 'user',
            groupType: GroupType.dean,
          ))
      .toList();

  var allEntries = [...entries, ...eventEntries];

  if (hideRes) {
    allEntries = allEntries.where((e) => !e.isReservation).toList();
  }

  allEntries.sort((a, b) => a.startTime.compareTo(b.startTime));
  return allEntries;
});

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

// ---- Refresh State ----

final isRefreshingProvider = StateProvider<bool>((ref) => false);

final refreshErrorProvider = StateProvider<String?>((ref) => null);

// ---- Refresh info ----

class RefreshInfo {
  final DateTime? lastRefreshAt;
  final String? status;
  final String? error;

  const RefreshInfo({
    required this.lastRefreshAt,
    required this.status,
    required this.error,
  });

  bool get hasData => lastRefreshAt != null || status != null;
}

final refreshInfoProvider =
    FutureProvider.autoDispose<RefreshInfo>((ref) async {
  final repo = ref.watch(scheduleRepositoryProvider);
  final lastRefreshAtRaw =
      await repo.getAppSetting(ScheduleRepository.lastRefreshAtKey);
  final status =
      await repo.getAppSetting(ScheduleRepository.lastRefreshStatusKey);
  final errorRaw =
      await repo.getAppSetting(ScheduleRepository.lastRefreshErrorKey);

  return RefreshInfo(
    lastRefreshAt:
        lastRefreshAtRaw == null ? null : DateTime.tryParse(lastRefreshAtRaw),
    status: status,
    error: errorRaw == null || errorRaw.trim().isEmpty ? null : errorRaw,
  );
});

// ---- Class type colors ----

final classTypeColorsProvider =
    AsyncNotifierProvider<ClassTypeColorsNotifier, Map<String, Color>>(
        ClassTypeColorsNotifier.new);

class ClassTypeColorsNotifier extends AsyncNotifier<Map<String, Color>> {
  @override
  Future<Map<String, Color>> build() async {
    final repo = ref.watch(scheduleRepositoryProvider);
    final colors = <String, Color>{};

    for (final option in AppColors.scheduleColorOptions) {
      final raw =
          await repo.getAppSetting(AppColors.colorSettingKey(option.key));
      final parsed = raw == null ? null : int.tryParse(raw);
      if (parsed != null) {
        colors[option.key] = Color(parsed);
      }
    }

    return colors;
  }

  Future<void> setColor(String key, Color color) async {
    await ref.read(scheduleRepositoryProvider).setAppSetting(
        AppColors.colorSettingKey(key), color.toARGB32().toString());
    ref.invalidateSelf();
    ref.invalidate(todayScheduleProvider);
  }

  Future<void> resetColor(String key) async {
    final option = AppColors.scheduleColorOptions.firstWhere(
      (option) => option.key == key,
    );
    await setColor(key, option.defaultColor);
  }
}

// ---- Subject Filters ----

final subjectFiltersProvider =
    AsyncNotifierProvider<SubjectFiltersNotifier, List<SubjectFilter>>(
        SubjectFiltersNotifier.new);

class SubjectFiltersNotifier extends AsyncNotifier<List<SubjectFilter>> {
  @override
  Future<List<SubjectFilter>> build() async {
    return ref.watch(scheduleRepositoryProvider).getSubjectFilters();
  }

  Future<void> addFilter(SubjectFilter filter) async {
    await ref.read(scheduleRepositoryProvider).upsertSubjectFilter(filter);
    ref.invalidateSelf();
  }

  Future<void> removeFilter(int id) async {
    await ref.read(scheduleRepositoryProvider).deleteSubjectFilter(id);
    ref.invalidateSelf();
  }
}

// ---- Settings ----

final hideReservationsProvider =
    AsyncNotifierProvider<HideReservationsNotifier, bool>(
        HideReservationsNotifier.new);

class HideReservationsNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    return ref.watch(scheduleRepositoryProvider).getHideReservations();
  }

  Future<void> toggle() async {
    final current = await future;
    await ref.read(scheduleRepositoryProvider).setHideReservations(!current);
    ref.invalidateSelf();
    ref.invalidate(todayScheduleProvider);
  }
}

// ---- User Events ----

final userEventsProvider =
    AsyncNotifierProvider<UserEventsNotifier, List<UserEvent>>(
        UserEventsNotifier.new);

class UserEventsNotifier extends AsyncNotifier<List<UserEvent>> {
  @override
  Future<List<UserEvent>> build() async {
    return ref.watch(scheduleRepositoryProvider).getUserEvents();
  }

  Future<void> add(UserEvent event) async {
    await ref.read(scheduleRepositoryProvider).addUserEvent(event);
    ref.invalidateSelf();
    ref.invalidate(todayScheduleProvider);
  }

  Future<void> updateUserEvent(UserEvent event) async {
    await ref.read(scheduleRepositoryProvider).updateUserEvent(event);
    ref.invalidateSelf();
    ref.invalidate(todayScheduleProvider);
  }

  Future<void> delete(int id) async {
    await ref.read(scheduleRepositoryProvider).deleteUserEvent(id);
    ref.invalidateSelf();
    ref.invalidate(todayScheduleProvider);
  }
}
