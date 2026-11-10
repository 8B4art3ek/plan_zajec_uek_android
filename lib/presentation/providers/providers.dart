// lib/presentation/providers/providers.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../core/refresh_settings.dart';
import '../../data/datasources/background_service.dart';
import '../../data/datasources/auth_service.dart';
import '../../data/datasources/local_database.dart';
import '../../data/datasources/schedule_parser.dart';
import '../../data/datasources/schedule_remote_datasource.dart';
import '../../data/repositories/schedule_repository_impl.dart';
import '../../domain/entities/group.dart';
import '../../domain/entities/schedule_entry.dart';
import '../../domain/entities/subject_filter.dart';
import '../../domain/entities/user_event.dart';
import '../../domain/entities/university.dart';

// ---- Infrastructure Providers ----

final localDatabaseProvider = Provider<LocalDatabase>((ref) {
  final db = LocalDatabase();
  ref.onDispose(() => db.close());
  return db;
});

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final remoteDatasourceProvider = Provider<ScheduleRemoteDatasource>((ref) {
  final remote = ScheduleRemoteDatasource();
  ref.onDispose(remote.close);
  return remote;
});

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

final pendingGroupSetupProvider = StateProvider<bool>((ref) => false);

final universityProvider =
    AsyncNotifierProvider<UniversityNotifier, University?>(
        UniversityNotifier.new);

class UniversityNotifier extends AsyncNotifier<University?> {
  static const settingKey = 'selected_university';
  @override
  Future<University?> build() async {
    final repo = ref.watch(scheduleRepositoryProvider);
    final saved = University.fromStorage(await repo.getAppSetting(settingKey));
    if (saved != null) return saved;
    // Existing accounts were all created for UEK; retain their configuration.
    if (await ref.watch(credentialsProvider.future) != null) {
      await repo.setAppSetting(settingKey, University.uek.id);
      return University.uek;
    }
    return null;
  }

  Future<void> select(University university) async {
    await ref
        .read(scheduleRepositoryProvider)
        .setAppSetting(settingKey, university.id);
    state = AsyncData(university);
  }
}

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
    ref.invalidate(todayScheduleProvider);
  }

  Future<void> updateGroup(Group group) async {
    await ref.read(scheduleRepositoryProvider).updateGroup(group);
    ref.invalidateSelf();
    ref.invalidate(todayScheduleProvider);
  }

  Future<void> deleteGroup(String groupId) async {
    await ref.read(scheduleRepositoryProvider).deleteGroup(groupId);
    ref.invalidateSelf();
    ref.invalidate(todayScheduleProvider);
    ref.invalidate(subjectFiltersProvider);
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

// ---- Refresh info ----

class RefreshInfo {
  final DateTime? lastRefreshAt;
  final String? status;
  final String? error;
  final DateTime? nextRetryAt;

  const RefreshInfo({
    required this.lastRefreshAt,
    required this.status,
    required this.error,
    this.nextRetryAt,
  });

  bool get hasFailure =>
      status == 'partial_error' || status == 'partial_changed';
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
    nextRetryAt: await repo.nextAutomaticRefreshAt(),
  );
});

// ---- Class type colors ----

const _themeSettingKey = 'app_theme';

final refreshMinutesProvider =
    AsyncNotifierProvider<RefreshMinutesNotifier, int>(
        RefreshMinutesNotifier.new);

final refreshSchedulerProvider = Provider<Future<void> Function(int)>((ref) =>
    (minutes) => BackgroundService.schedulePeriodicRefresh(minutes: minutes));

class RefreshMinutesNotifier extends AsyncNotifier<int> {
  @override
  Future<int> build() =>
      ref.watch(scheduleRepositoryProvider).automaticRefreshMinutes();

  Future<void> setMinutes(int minutes) async {
    if (!RefreshSettings.options.contains(minutes)) {
      throw ArgumentError.value(minutes);
    }
    final repo = ref.read(scheduleRepositoryProvider);
    final previous = await repo.automaticRefreshMinutes();
    state = const AsyncLoading();
    try {
      await repo.setAppSetting(RefreshSettings.key, '$minutes');
      await ref.read(refreshSchedulerProvider)(minutes);
    } catch (_) {
      await repo.setAppSetting(RefreshSettings.key, '$previous');
      state = AsyncData(previous);
      rethrow;
    }
    state = AsyncData(minutes);
  }
}

final customThemeColorsProvider =
    AsyncNotifierProvider<CustomThemeColorsNotifier, Map<String, Color>>(
        CustomThemeColorsNotifier.new);

class CustomThemeColorsNotifier extends AsyncNotifier<Map<String, Color>> {
  static const keys = ['primary', 'secondary', 'background', 'surface'];
  @override
  Future<Map<String, Color>> build() async {
    final repo = ref.watch(scheduleRepositoryProvider);
    final colors = <String, Color>{};
    for (final key in keys) {
      final raw =
          int.tryParse(await repo.getAppSetting('theme_color_$key') ?? '');
      if (raw != null && raw >= 0 && raw <= 0xFFFFFFFF) {
        colors[key] = Color(raw).withAlpha(255);
      }
    }
    return colors;
  }

  Future<void> setColor(String key, Color color) async {
    if (!keys.contains(key)) throw ArgumentError.value(key);
    await ref.read(scheduleRepositoryProvider).setAppSetting(
        'theme_color_$key', '${color.withAlpha(255).toARGB32()}');
    state = AsyncData({...?state.valueOrNull, key: color.withAlpha(255)});
  }

  Future<void> reset() async {
    final repo = ref.read(scheduleRepositoryProvider);
    for (final key in keys) {
      await repo.setAppSetting('theme_color_$key', '');
    }
    state = const AsyncData({});
    if (await ref.read(appThemeProvider.future) == AppThemeKind.custom) {
      await ref.read(appThemeProvider.notifier).setTheme(AppThemeKind.midnight);
    }
  }

  Future<void> saveTheme(Map<String, Color> colors) async {
    if (keys.any((key) => !colors.containsKey(key))) {
      throw ArgumentError('Brak kompletu kolorów motywu.');
    }
    await ref.read(appThemeProvider.future);
    final repo = ref.read(scheduleRepositoryProvider);
    for (final key in keys) {
      final color = colors[key];
      if (color == null) throw ArgumentError.value(key);
      await repo.setAppSetting(
          'theme_color_$key', '${color.withAlpha(255).toARGB32()}');
    }
    state = AsyncData(Map.of(colors));
    await ref.read(appThemeProvider.notifier).setTheme(AppThemeKind.custom);
  }
}

final appThemeProvider = AsyncNotifierProvider<AppThemeNotifier, AppThemeKind>(
  AppThemeNotifier.new,
);

class AppThemeNotifier extends AsyncNotifier<AppThemeKind> {
  @override
  Future<AppThemeKind> build() async {
    final raw = await ref
        .watch(scheduleRepositoryProvider)
        .getAppSetting(_themeSettingKey);
    return AppThemeKind.fromStorage(raw);
  }

  Future<void> setTheme(AppThemeKind theme) async {
    await ref
        .read(scheduleRepositoryProvider)
        .setAppSetting(_themeSettingKey, theme.storageValue);
    state = AsyncData(theme);
  }
}

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
  }

  Future<void> resetColor(String key) async {
    final option = AppColors.scheduleColorOptions.firstWhere(
      (option) => option.key == key,
    );
    await setColor(key, option.defaultColor);
  }
}

// ---- Subject Filters ----

final filterSubjectsProvider =
    FutureProvider.autoDispose.family<List<String>, String>((ref, groupId) {
  ref.watch(groupsProvider);
  ref.watch(refreshInfoProvider);
  return ref.watch(scheduleRepositoryProvider).getSubjectsForGroup(groupId);
});

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
    ref.invalidate(todayScheduleProvider);
  }

  Future<void> removeFilter(int id) async {
    await ref.read(scheduleRepositoryProvider).deleteSubjectFilter(id);
    ref.invalidateSelf();
    ref.invalidate(todayScheduleProvider);
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
