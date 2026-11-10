// lib/data/repositories/schedule_repository_impl.dart

import 'dart:convert';
import '../../core/refresh_settings.dart';
import 'package:crypto/crypto.dart';
import '../../domain/entities/group.dart';
import '../../domain/entities/schedule_entry.dart';
import '../../domain/entities/schedule_change.dart';
import '../../domain/entities/subject_filter.dart';
import '../../domain/entities/usos_import.dart';
import '../../domain/entities/user_event.dart';
import '../datasources/auth_service.dart';
import '../datasources/local_database.dart';
import '../datasources/schedule_group_resolver.dart';
import '../datasources/schedule_parser.dart';
import '../datasources/schedule_remote_datasource.dart';

/// Thrown when credentials are missing or invalid.
class AuthException implements Exception {
  final String message;
  AuthException(this.message);
  @override
  String toString() => 'AuthException: $message';
}

class ScheduleRefreshResult {
  final bool changed;
  final List<String> failures;
  final List<ScheduleChange> changes;

  ScheduleRefreshResult(
      {required this.changed,
      required List<String> failures,
      List<ScheduleChange> changes = const []})
      : failures = List.unmodifiable(failures),
        changes = List.unmodifiable(changes);

  bool get isSuccessful => failures.isEmpty;
}

class ScheduleRepository {
  static const lastRefreshAtKey = 'last_refresh_at';
  static const lastRefreshStatusKey = 'last_refresh_status';
  static const lastRefreshErrorKey = 'last_refresh_error';
  static const refreshFailureCountKey = 'refresh_failure_count';
  static const nextRefreshAttemptKey = 'next_refresh_attempt';
  static const planPeriodKey = 'plan_period';
  static const defaultPlanPeriod = 3;
  static const planPeriods = [1, 2, 3, 4];

  final LocalDatabase _db;
  final ScheduleRemoteDatasource _remote;
  final ScheduleParser _parser;
  final AuthService _auth;

  ScheduleRepository({
    required LocalDatabase db,
    required ScheduleRemoteDatasource remote,
    required ScheduleParser parser,
    required AuthService auth,
  })  : _db = db,
        _remote = remote,
        _parser = parser,
        _auth = auth;

  // ========== GROUPS ==========

  Future<List<Group>> getGroups() => _db.getAllGroups();

  Future<int> automaticRefreshMinutes() async =>
      RefreshSettings.parse(await getAppSetting(RefreshSettings.key));

  Future<DateTime?> automaticRefreshDueAt() async => RefreshSettings.dueAt(
      await automaticRefreshMinutes(),
      DateTime.tryParse(await getAppSetting(lastRefreshAtKey) ?? ''),
      await nextAutomaticRefreshAt());

  Future<DateTime?> nextAutomaticRefreshAt() async =>
      DateTime.tryParse(await getAppSetting(nextRefreshAttemptKey) ?? '');

  Future<void> addGroup(Group group) => _db.insertGroup(group);

  Future<void> updateGroup(Group group) => _db.updateGroup(group);

  Future<void> deleteGroup(String groupId) => _db.deleteGroup(groupId);

  Future<UsosImportResult> resolveUsosGroups(UsosImportData data) async {
    final creds = await _auth.getCredentials();
    if (creds == null) throw AuthException('Brak danych logowania');

    final resolver = ScheduleGroupResolver(remote: _remote);
    final resolution = await resolver.resolve(
      data: data,
      username: creds.username,
      password: creds.password,
    );

    return resolution;
  }

  Future<UsosImportResult> importResolvedUsosGroups(
    List<ResolvedUsosGroup> resolvedGroups,
  ) async {
    final refreshFailures = <UsosImportFailure>[];
    for (final resolved in resolvedGroups) {
      final group = resolved.toGroup();
      await _db.insertGroup(group);
      try {
        await refreshGroup(group);
      } catch (e) {
        refreshFailures.add(
          UsosImportFailure(group: resolved, message: e.toString()),
        );
      }
    }

    return UsosImportResult(
      imported: resolvedGroups,
      unresolved: const [],
      refreshFailures: refreshFailures,
    );
  }

  // ========== SCHEDULE FETCH ==========

  /// Returns true if schedule changed
  Future<bool> refreshGroup(Group group) async {
    return (await _refreshGroup(group)).$1;
  }

  Future<(bool, List<ScheduleChange>)> _refreshGroup(Group group) async {
    final creds = await _auth.getCredentials();
    if (creds == null) throw AuthException('Brak danych logowania');
    final planPeriod = await getPlanPeriod();

    final html = await _remote.fetchScheduleHtml(
      groupId: group.groupId,
      username: creds.username,
      password: creds.password,
      okres: planPeriod,
    );

    final newEntries = _parser.parse(html, group.groupId, group.groupType);

    // Compare with existing entries
    final existing = await _db.getEntriesForGroup(group.groupId);
    final changed = _computeHash(existing) != _computeHash(newEntries);
    final previousPeriod =
        await _db.getSetting('schedule_period_${group.groupId}');
    var changes = const <ScheduleChange>[];
    if (changed &&
        !(existing.isEmpty && previousPeriod == null) &&
        (previousPeriod == null || previousPeriod == '$planPeriod')) {
      final filters = await _db.getAllSubjectFilters();
      final hidden = filters
          .where((filter) => filter.groupId == group.groupId && filter.isHidden)
          .map((filter) => filter.subject)
          .toSet();
      final hideReservations = await getHideReservations();
      bool visible(ScheduleEntry entry) =>
          !hidden.contains(entry.subject) &&
          !(hideReservations && entry.isReservation);
      changes = ScheduleChange.compare(existing.where(visible).toList(),
          newEntries.where(visible).toList(), DateTime.now());
    }

    await _db.saveScheduleEntries(newEntries, group.groupId,
        changes: changes, period: planPeriod);

    return (changed, changes);
  }

  Future<ScheduleRefreshResult> refreshAllGroups() async {
    bool anyChanged = false;
    final failures = <String>[];
    final changes = <ScheduleChange>[];

    try {
      final groups = await _db.getAllGroups();
      final enabledGroups = groups.where((g) => g.isEnabled).toList();
      if (enabledGroups.isEmpty) {
        return ScheduleRefreshResult(changed: false, failures: const []);
      }

      for (final group in enabledGroups) {
        try {
          final result = await _refreshGroup(group);
          if (result.$1) anyChanged = true;
          changes.addAll(result.$2);
        } catch (e) {
          failures.add('${group.displayName}: $e');
        }
      }
    } catch (e) {
      await _recordRefreshResult(false, [e.toString()]);
      rethrow;
    }

    await _recordRefreshResult(anyChanged, failures);
    return ScheduleRefreshResult(
        changed: anyChanged, failures: failures, changes: changes);
  }

  // ========== ENTRIES ==========

  Future<List<ScheduleEntry>> getSavedEntries() => _db.getSavedEntries();

  Future<List<ScheduleChange>> getPendingScheduleChanges() =>
      _db.getPendingScheduleChanges();

  Future<void> acknowledgeScheduleChanges(List<int> ids) =>
      _db.acknowledgeScheduleChanges(ids);

  Future<List<ScheduleEntry>> getEntriesForDate(DateTime date) async {
    final entries = await _db.getEntriesForDate(date);
    final filters = await _db.getAllSubjectFilters();
    final groups = await _db.getAllGroups();
    final enabledIds =
        groups.where((g) => g.isEnabled).map((g) => g.groupId).toSet();
    final hiddenSubjects = {
      for (final filter in filters)
        if (filter.isHidden) (filter.groupId, filter.subject),
    };
    return entries
        .where(
          (entry) =>
              enabledIds.contains(entry.groupId) &&
              !hiddenSubjects.contains((entry.groupId, entry.subject)),
        )
        .toList();
  }

  // ========== USER EVENTS ==========

  Future<List<UserEvent>> getUserEvents() => _db.getAllUserEvents();

  Future<void> addUserEvent(UserEvent event) => _db.insertUserEvent(event);

  Future<void> updateUserEvent(UserEvent event) => _db.updateUserEvent(event);

  Future<void> deleteUserEvent(int id) => _db.deleteUserEvent(id);

  // ========== SUBJECT FILTERS ==========

  Future<List<SubjectFilter>> getSubjectFilters() => _db.getAllSubjectFilters();

  Future<List<String>> getSubjectsForGroup(String groupId) async {
    final entries = await _db.getEntriesForGroup(groupId);
    final subjects = entries
        .map((entry) => entry.subject)
        .where((subject) => subject.trim().isNotEmpty)
        .toSet()
        .toList();
    subjects.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return subjects;
  }

  Future<void> upsertSubjectFilter(SubjectFilter filter) =>
      _db.upsertSubjectFilter(filter);

  Future<void> deleteSubjectFilter(int id) => _db.deleteSubjectFilter(id);

  // ========== SETTINGS ==========

  Future<bool> getHideReservations() async {
    final val = await _db.getSetting('hide_reservations');
    return val == '1';
  }

  Future<void> setHideReservations(bool hide) =>
      _db.setSetting('hide_reservations', hide ? '1' : '0');

  Future<int> getPlanPeriod() async {
    final value = await _db.getSetting(planPeriodKey);
    final period = int.tryParse(value ?? '');
    return _isValidPlanPeriod(period) ? period! : defaultPlanPeriod;
  }

  Future<void> setPlanPeriod(int period) {
    if (!_isValidPlanPeriod(period)) {
      throw ArgumentError.value(
          period, 'period', 'Okres musi mieć wartość 1, 2, 3 lub 4.');
    }
    return _db.setSetting(planPeriodKey, period.toString());
  }

  Future<String?> getAppSetting(String key) => _db.getSetting(key);

  Future<void> setAppSetting(String key, String value) =>
      _db.setSetting(key, value);

  // ========== HELPERS ==========

  bool _isValidPlanPeriod(int? period) => planPeriods.contains(period);

  String _computeHash(List<ScheduleEntry> entries) {
    final sorted = List.of(entries)..sort((a, b) => a.id.compareTo(b.id));
    final raw = sorted.map(_entryFingerprint).join('|');
    return sha256.convert(utf8.encode(raw)).toString();
  }

  String _entryFingerprint(ScheduleEntry e) {
    return [
      e.id,
      e.subject,
      e.classType,
      e.lecturer,
      e.room,
      e.date.toIso8601String(),
      e.startTime,
      e.endTime,
      e.weekday,
      e.durationHours.toString(),
      e.groupId,
      e.groupType.dbValue,
      e.isMoved ? '1' : '0',
      e.originalDate?.toIso8601String() ?? '',
      e.originalStartTime ?? '',
      e.originalEndTime ?? '',
      e.newDate?.toIso8601String() ?? '',
      e.newStartTime ?? '',
      e.newEndTime ?? '',
    ].join('\u001f');
  }

  Future<void> _recordRefreshResult(
    bool anyChanged,
    List<String> failures,
  ) async {
    final status = (failures.isEmpty
        ? (anyChanged ? 'changed' : 'ok')
        : (anyChanged ? 'partial_changed' : 'partial_error'));

    if (failures.isEmpty) {
      await _db.setSetting(lastRefreshAtKey, DateTime.now().toIso8601String());
      await _db.setSetting(refreshFailureCountKey, '0');
      await _db.setSetting(nextRefreshAttemptKey, '');
    } else {
      final count =
          (int.tryParse(await _db.getSetting(refreshFailureCountKey) ?? '') ??
                  0) +
              1;
      const delays = [5, 15, 30, 60];
      final minutes = delays[(count - 1).clamp(0, delays.length - 1)];
      await _db.setSetting(refreshFailureCountKey, '$count');
      await _db.setSetting(nextRefreshAttemptKey,
          DateTime.now().add(Duration(minutes: minutes)).toIso8601String());
    }
    await _db.setSetting(lastRefreshStatusKey, status);
    await _db.setSetting(lastRefreshErrorKey, failures.join('\n'));
  }
}
