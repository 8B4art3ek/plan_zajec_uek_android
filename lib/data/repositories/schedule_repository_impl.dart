// lib/data/repositories/schedule_repository_impl.dart

import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../../domain/entities/group.dart';
import '../../domain/entities/schedule_entry.dart';
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

class ScheduleRepository {
  static const lastRefreshAtKey = 'last_refresh_at';
  static const lastRefreshStatusKey = 'last_refresh_status';
  static const lastRefreshErrorKey = 'last_refresh_error';

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

  Future<void> addGroup(Group group) => _db.insertGroup(group);

  Future<void> updateGroup(Group group) => _db.updateGroup(group);

  Future<void> deleteGroup(String groupId) => _db.deleteGroup(groupId);

  Future<UsosImportResult> importUsosGroups(UsosImportData data) async {
    final resolution = await resolveUsosGroups(data);
    final imported = await importResolvedUsosGroups(resolution.imported);
    return resolution.copyWith(refreshFailures: imported.refreshFailures);
  }

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
    final creds = await _auth.getCredentials();
    if (creds == null) throw AuthException('Brak danych logowania');

    final html = await _remote.fetchScheduleHtml(
      groupId: group.groupId,
      username: creds.username,
      password: creds.password,
    );

    final newEntries = _parser.parse(html, group.groupId, group.groupType);

    // Compare with existing entries
    final existing = await _db.getAllEntries();
    final existingForGroup =
        existing.where((e) => e.groupId == group.groupId).toList();

    final changed = _hasChanged(existingForGroup, newEntries);

    await _db.saveScheduleEntries(newEntries, group.groupId);

    // Store hash for change detection
    final newHash = _computeHash(newEntries);
    await _db.setSetting('hash_${group.groupId}', newHash);

    return changed;
  }

  Future<bool> refreshAllGroups() async {
    bool anyChanged = false;
    final failures = <String>[];

    try {
      final groups = await _db.getAllGroups();
      final enabledGroups = groups.where((g) => g.isEnabled).toList();

      for (final group in enabledGroups) {
        try {
          final changed = await refreshGroup(group);
          if (changed) anyChanged = true;
        } catch (e) {
          failures.add('${group.displayName}: $e');
        }
      }
    } catch (e) {
      await recordRefreshFailure(e);
      rethrow;
    }

    await _recordRefreshResult(anyChanged, failures);
    return anyChanged;
  }

  // ========== ENTRIES ==========

  Future<List<ScheduleEntry>> getEntriesForDate(DateTime date) async {
    final entries = await _db.getEntriesForDate(date);
    final filters = await _db.getAllSubjectFilters();
    return _applyFilters(entries, filters);
  }

  Future<List<ScheduleEntry>> getAllEntries() async {
    final entries = await _db.getAllEntries();
    final filters = await _db.getAllSubjectFilters();
    return _applyFilters(entries, filters);
  }

  List<ScheduleEntry> _applyFilters(
    List<ScheduleEntry> entries,
    List<SubjectFilter> filters,
  ) {
    if (filters.isEmpty) return entries;

    return entries.where((entry) {
      for (final filter in filters) {
        if (filter.isHidden &&
            filter.groupId == entry.groupId &&
            filter.subject == entry.subject) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  // ========== USER EVENTS ==========

  Future<List<UserEvent>> getUserEvents() => _db.getAllUserEvents();

  Future<void> addUserEvent(UserEvent event) => _db.insertUserEvent(event);

  Future<void> updateUserEvent(UserEvent event) => _db.updateUserEvent(event);

  Future<void> deleteUserEvent(int id) => _db.deleteUserEvent(id);

  // ========== SUBJECT FILTERS ==========

  Future<List<SubjectFilter>> getSubjectFilters() => _db.getAllSubjectFilters();

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

  Future<String?> getAppSetting(String key) => _db.getSetting(key);

  Future<void> setAppSetting(String key, String value) =>
      _db.setSetting(key, value);

  Future<void> recordRefreshFailure(Object error) =>
      _recordRefreshResult(false, [error.toString()], statusOverride: 'error');

  // ========== HELPERS ==========

  bool _hasChanged(List<ScheduleEntry> existing, List<ScheduleEntry> updated) {
    return _computeHash(existing) != _computeHash(updated);
  }

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
    List<String> failures, {
    String? statusOverride,
  }) async {
    final status = statusOverride ??
        (failures.isEmpty
            ? (anyChanged ? 'changed' : 'ok')
            : (anyChanged ? 'partial_changed' : 'partial_error'));

    await _db.setSetting(lastRefreshAtKey, DateTime.now().toIso8601String());
    await _db.setSetting(lastRefreshStatusKey, status);
    await _db.setSetting(lastRefreshErrorKey, failures.join('\n'));
  }
}
