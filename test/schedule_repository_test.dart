import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plan_zajec_uek/data/datasources/auth_service.dart';
import 'package:plan_zajec_uek/data/datasources/local_database.dart';
import 'package:plan_zajec_uek/data/datasources/schedule_parser.dart';
import 'package:plan_zajec_uek/data/datasources/schedule_remote_datasource.dart';
import 'package:plan_zajec_uek/data/repositories/schedule_repository_impl.dart';
import 'package:plan_zajec_uek/domain/entities/group.dart';
import 'package:plan_zajec_uek/domain/entities/schedule_entry.dart';
import 'package:plan_zajec_uek/domain/entities/schedule_change.dart';
import 'package:plan_zajec_uek/domain/entities/subject_filter.dart';
import 'package:plan_zajec_uek/domain/entities/user_event.dart';
import 'package:plan_zajec_uek/presentation/providers/providers.dart';

final _date = DateTime(2026, 10, 17);
const _group = Group(groupId: '1', groupType: GroupType.dean);

ScheduleEntry _entry(String groupId) => ScheduleEntry(
      id: 'entry_$groupId',
      subject: 'Matematyka',
      classType: 'wykład',
      lecturer: 'Prowadzący',
      room: '1',
      date: _date,
      startTime: '09:00',
      endTime: '10:30',
      weekday: 'sobota',
      durationHours: 2,
      groupId: groupId,
      groupType: GroupType.dean,
    );

class _Database extends LocalDatabase {
  final groups = <Group>[_group];
  final entries = <ScheduleEntry>[_entry('1')];
  final filters = <SubjectFilter>[];
  final settings = <String, String>{};
  final pendingChanges = <ScheduleChange>[];

  @override
  Future<List<Group>> getAllGroups() async => [...groups];
  @override
  Future<void> updateGroup(Group group) async {
    groups[groups.indexWhere((g) => g.groupId == group.groupId)] = group;
  }

  @override
  Future<void> deleteGroup(String id) async {
    groups.removeWhere((g) => g.groupId == id);
    entries.removeWhere((e) => e.groupId == id);
    filters.removeWhere((f) => f.groupId == id);
  }

  @override
  Future<List<ScheduleEntry>> getEntriesForDate(DateTime date) async =>
      [...entries];
  @override
  Future<List<ScheduleEntry>> getEntriesForGroup(String id) async =>
      entries.where((e) => e.groupId == id).toList();
  @override
  Future<void> saveScheduleEntries(List<ScheduleEntry> updated, String id,
      {List<ScheduleChange> changes = const [], int? period}) async {
    entries.removeWhere((e) => e.groupId == id);
    entries.addAll(updated);
    pendingChanges.addAll(changes);
    if (period != null) settings['schedule_period_$id'] = '$period';
  }

  @override
  Future<List<ScheduleChange>> getPendingScheduleChanges() async =>
      [...pendingChanges];

  @override
  Future<List<SubjectFilter>> getAllSubjectFilters() async => [...filters];
  @override
  Future<void> deleteSubjectFilter(int id) async =>
      filters.removeWhere((f) => f.id == id);
  @override
  Future<void> upsertSubjectFilter(SubjectFilter filter) async =>
      filters.add(filter);
  @override
  Future<List<UserEvent>> getAllUserEvents() async => [];
  @override
  Future<String?> getSetting(String key) async => settings[key];
  @override
  Future<void> setSetting(String key, String value) async {
    settings[key] = value;
  }
}

class _Auth extends AuthService {
  @override
  Future<Credentials?> getCredentials() async =>
      const Credentials(username: 'test', password: 'test');
}

class _Remote extends ScheduleRemoteDatasource {
  final failedIds = <String>{};
  final requestedIds = <String>[];
  int? period;
  String html = '<table class="zajecia"></table>';
  @override
  Future<String> fetchScheduleHtml(
      {required String groupId,
      required String username,
      required String password,
      int okres = 3}) async {
    requestedIds.add(groupId);
    period = okres;
    if (failedIds.contains(groupId)) throw Exception('Offline');
    return html;
  }
}

void main() {
  late _Database db;
  late _Remote remote;
  late ScheduleRepository repo;
  setUp(() {
    db = _Database();
    remote = _Remote();
    repo = ScheduleRepository(
        db: db, remote: remote, parser: ScheduleParser(), auth: _Auth());
  });
  tearDown(() => remote.close());

  test(
      'filter dropdown lists unique subjects of its group including hidden ones',
      () async {
    db.entries.addAll([
      _entry('1').copyWith(classType: 'ćwiczenia'),
      _entry('1').copyWith(subject: 'Angielski'),
      _entry('2').copyWith(subject: 'Tylko inna grupa'),
      _entry('1').copyWith(subject: '  '),
    ]);
    db.filters.add(const SubjectFilter(
        subject: 'Matematyka', groupId: '1', isHidden: true));
    expect(await repo.getSubjectsForGroup('1'), ['Angielski', 'Matematyka']);
    expect(await repo.getSubjectsForGroup('2'), ['Tylko inna grupa']);
    expect(await repo.getSubjectsForGroup('missing'), isEmpty);
  });

  test(
      'first import is baseline, later changes survive unchanged refresh and period switches',
      () async {
    final now = DateTime.now();
    final date = DateTime(now.year, now.month, now.day + 1)
        .toIso8601String()
        .substring(0, 10);
    String schedule(String room) =>
        '<table class="zajecia"><tr><td>$date</td><td>Wt 09:00 - 10:30 (2g.)</td><td>Matematyka</td><td>wykład</td><td>Prowadzący</td><td>$room</td></tr></table>';
    db.entries.clear();
    remote.html = schedule('Sala A');
    final initialResult = await repo.refreshAllGroups();
    expect(initialResult.changes, isEmpty);
    expect(db.pendingChanges, isEmpty);
    remote.html = schedule('Sala B');
    final changedResult = await repo.refreshAllGroups();
    expect(changedResult.changes, hasLength(1));
    expect(db.pendingChanges, hasLength(1));
    expect(db.pendingChanges.single.description, contains('Sala A'));
    expect(db.pendingChanges.single.description, contains('Sala B'));
    expect((await repo.refreshAllGroups()).changes, isEmpty);
    expect(db.pendingChanges, hasLength(1));
    await repo.setPlanPeriod(4);
    remote.html = schedule('Sala C');
    await repo.refreshGroup(_group);
    expect(db.pendingChanges, hasLength(1));
    remote.failedIds.add('1');
    await expectLater(repo.refreshGroup(_group), throwsException);
    expect(db.pendingChanges, hasLength(1));
    expect(db.entries.single.room, 'Sala C');
  });

  test('hidden subjects produce no notification details', () async {
    final now = DateTime.now();
    final date = DateTime(now.year, now.month, now.day + 1);
    db.entries[0] = db.entries[0].copyWith(date: date);
    db.filters.add(const SubjectFilter(
        subject: 'Matematyka', groupId: '1', isHidden: true));
    final result = await repo.refreshAllGroups();
    expect(result.changed, isTrue);
    expect(result.changes, isEmpty);
    expect(db.pendingChanges, isEmpty);
  });

  test('supports all four periods and refreshes groups with saved period 4',
      () async {
    expect(ScheduleRepository.planPeriods, [1, 2, 3, 4]);
    for (final period in ScheduleRepository.planPeriods) {
      await repo.setPlanPeriod(period);
      expect(await repo.getPlanPeriod(), period);
    }
    await repo.refreshAllGroups();
    expect(remote.period, 4);
    expect(db.settings[ScheduleRepository.planPeriodKey], '4');
    for (final invalid in [0, 5]) {
      expect(() => repo.setPlanPeriod(invalid), throwsArgumentError);
    }
    expect(await repo.getPlanPeriod(), 4);
  });

  test('excludes disabled groups and applies filters only to their group',
      () async {
    db.groups.add(const Group(groupId: '2', groupType: GroupType.language));
    db.entries.add(_entry('2'));
    db.filters.add(const SubjectFilter(
        id: 1, subject: 'Matematyka', groupId: '1', isHidden: true));
    expect((await repo.getEntriesForDate(_date)).map((e) => e.groupId), ['2']);
    await repo.updateGroup(db.groups[1].copyWith(isEnabled: false));
    expect(await repo.getEntriesForDate(_date), isEmpty);
  });

  test('failed refresh preserves entries and last successful timestamp',
      () async {
    db.settings[ScheduleRepository.lastRefreshAtKey] = '2026-10-16T10:00:00';
    remote.failedIds.add('1');
    final result = await repo.refreshAllGroups();
    expect(result.isSuccessful, isFalse);
    expect(result.failures.single, contains('Offline'));
    expect(db.entries, hasLength(1));
    expect(db.settings[ScheduleRepository.lastRefreshAtKey],
        '2026-10-16T10:00:00');
  });

  test('HTTP 500 preserves cached plan and produces no change notification',
      () async {
    final server = ScheduleRemoteDatasource(
        client: MockClient((_) async => http.Response('Server error', 500)));
    addTearDown(server.close);
    final repository = ScheduleRepository(
        db: db, remote: server, parser: ScheduleParser(), auth: _Auth());
    db.settings[ScheduleRepository.lastRefreshAtKey] = '2026-10-21T10:00:00';
    final result = await repository.refreshAllGroups();
    expect(result.isSuccessful, isFalse);
    expect(result.changed, isFalse);
    expect(result.changes, isEmpty);
    expect(db.pendingChanges, isEmpty);
    expect(db.entries.single.subject, 'Matematyka');
    expect(db.settings[ScheduleRepository.lastRefreshAtKey],
        '2026-10-21T10:00:00');
    expect(await repository.nextAutomaticRefreshAt(), isNotNull);
  });

  test(
      'retry delay grows, survives repository recreation and resets on success',
      () async {
    remote.failedIds.add('1');
    for (final minutes in [5, 15, 30, 60, 60]) {
      final before = DateTime.now();
      await repo.refreshAllGroups();
      final retry = (await repo.nextAutomaticRefreshAt())!;
      expect(retry.difference(before).inSeconds,
          inInclusiveRange(minutes * 60, minutes * 60 + 2));
      final reopened = ScheduleRepository(
          db: db, remote: remote, parser: ScheduleParser(), auth: _Auth());
      expect(await reopened.nextAutomaticRefreshAt(), retry);
    }
    remote.failedIds.clear();
    expect((await repo.refreshAllGroups()).isSuccessful, isTrue);
    expect(await repo.nextAutomaticRefreshAt(), isNull);
    expect(db.settings[ScheduleRepository.refreshFailureCountKey], '0');
    remote.failedIds.add('1');
    await repo.refreshAllGroups();
    expect(db.settings[ScheduleRepository.refreshFailureCountKey], '1');
  });

  test('partial refresh reports both changes and errors', () async {
    db.groups.add(const Group(groupId: '2', groupType: GroupType.language));
    db.entries.add(_entry('2'));
    remote.failedIds.add('2');
    final result = await repo.refreshAllGroups();
    expect(result.changed, isTrue);
    expect(result.isSuccessful, isFalse);
    expect(db.settings[ScheduleRepository.lastRefreshAtKey], isNull);
    expect(db.settings[ScheduleRepository.lastRefreshStatusKey],
        'partial_changed');
    expect(db.entries.single.groupId, '2');
  });

  test('success records timestamp and clears previous error', () async {
    db.settings[ScheduleRepository.lastRefreshErrorKey] = 'Offline';
    await repo.setPlanPeriod(2);
    expect((await repo.refreshAllGroups()).isSuccessful, isTrue);
    expect(remote.period, 2);
    expect(db.settings[ScheduleRepository.lastRefreshAtKey], isNotNull);
    expect(db.settings[ScheduleRepository.lastRefreshErrorKey], isEmpty);
    expect(db.settings.keys.where((key) => key.startsWith('hash_')), isEmpty);
    expect((await repo.refreshAllGroups()).changed, isFalse);
  });

  test('disabled groups do not trigger requests or a successful timestamp',
      () async {
    db.groups[0] = _group.copyWith(isEnabled: false);
    await repo.refreshAllGroups();
    expect(remote.requestedIds, isEmpty);
    expect(db.settings, isEmpty);
  });

  test('group and filter mutations immediately invalidate the displayed day',
      () async {
    final container = ProviderContainer(
        overrides: [scheduleRepositoryProvider.overrideWithValue(repo)]);
    addTearDown(container.dispose);
    container.listen(todayScheduleProvider, (_, __) {});
    await container.read(groupsProvider.future);
    await container.read(subjectFiltersProvider.future);
    expect(await container.read(todayScheduleProvider.future), hasLength(1));
    await container
        .read(groupsProvider.notifier)
        .updateGroup(_group.copyWith(isEnabled: false));
    expect(await container.read(todayScheduleProvider.future), isEmpty);
    await container.read(groupsProvider.future);
    await container.read(groupsProvider.notifier).updateGroup(_group);
    expect(await container.read(todayScheduleProvider.future), hasLength(1));
    await container.read(subjectFiltersProvider.notifier).addFilter(
        const SubjectFilter(
            id: 1, subject: 'Matematyka', groupId: '1', isHidden: true));
    expect(await container.read(todayScheduleProvider.future), isEmpty);
    await container.read(subjectFiltersProvider.future);
    await container.read(subjectFiltersProvider.notifier).removeFilter(1);
    expect(await container.read(todayScheduleProvider.future), hasLength(1));
    await container.read(groupsProvider.future);
    await container.read(groupsProvider.notifier).deleteGroup('1');
    expect(await container.read(todayScheduleProvider.future), isEmpty);
  });
}
