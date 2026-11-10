import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:plan_zajec_uek/data/datasources/local_database.dart';
import 'package:plan_zajec_uek/domain/entities/group.dart';
import 'package:plan_zajec_uek/domain/entities/schedule_entry.dart';
import 'package:plan_zajec_uek/domain/entities/schedule_change.dart';

final _date = DateTime(2026, 10, 21);
ScheduleEntry _entry(String room) => ScheduleEntry(
    id: '1',
    subject: 'Matematyka',
    classType: 'CW',
    lecturer: 'Prowadzący',
    room: room,
    date: _date,
    startTime: '09:00',
    endTime: '10:30',
    weekday: '',
    durationHours: 2,
    groupId: '1',
    groupType: GroupType.dean);
ScheduleChange _change(String description) => ScheduleChange(
    groupId: '1',
    subject: 'Matematyka',
    description: description,
    detectedAt: _date);

void main() {
  late Directory directory;
  late DatabaseFactory factory;
  late LocalDatabase foreground;
  late LocalDatabase background;
  setUp(() async {
    sqfliteFfiInit();
    directory = await Directory.systemTemp.createTemp('uek-change-tests-');
    factory = createDatabaseFactoryFfi(noIsolate: true);
    await factory.setDatabasesPath(directory.path);
    foreground = LocalDatabase(factory: factory);
    background = LocalDatabase(factory: factory);
    await foreground
        .insertGroup(const Group(groupId: '1', groupType: GroupType.dean));
  });
  tearDown(() async {
    await foreground.close();
    await background.close();
    if (path.isWithin(
        Directory.systemTemp.absolute.path, directory.absolute.path)) {
      await directory.delete(recursive: true);
    }
  });

  test(
      'v3 migration preserves groups and schedule and creates pending-change storage',
      () async {
    await foreground.saveScheduleEntries([_entry('A')], '1');
    final old = await foreground.database;
    await old.execute('DROP TABLE schedule_changes');
    await old.setVersion(3);
    await foreground.close();
    expect((await foreground.getAllGroups()).single.groupId, '1');
    expect((await foreground.getEntriesForGroup('1')).single.room, 'A');
    expect(await foreground.getPendingScheduleChanges(), isEmpty);
    expect(await (await foreground.database).getVersion(), 4);
  });

  test(
      'background changes survive restart/no-op refresh and deduplicate until acknowledged',
      () async {
    await background.saveScheduleEntries([_entry('B')], '1',
        changes: [_change('A → B')], period: 4);
    await background.close();
    await foreground.saveScheduleEntries([_entry('B')], '1',
        changes: [_change('A → B')], period: 4);
    final seen = await foreground.getPendingScheduleChanges();
    expect(seen, hasLength(1));
    await foreground.saveScheduleEntries([_entry('C')], '1',
        changes: [_change('B → C')]);
    await foreground.acknowledgeScheduleChanges([seen.single.id!]);
    expect((await foreground.getPendingScheduleChanges()).single.description,
        'B → C');
    expect(await foreground.getSetting('schedule_period_1'), '4');
    await foreground.updateGroup(
        const Group(groupId: '1', groupType: GroupType.dean, isEnabled: false));
    expect(await foreground.getPendingScheduleChanges(), isEmpty);
    await foreground.deleteGroup('1');
    expect(await foreground.getSetting('schedule_period_1'), isNull);
    expect(
        await (await foreground.database).query('schedule_changes'), isEmpty);
  });

  test('schedule and changes roll back together if saving the journal fails',
      () async {
    await foreground.saveScheduleEntries([_entry('A')], '1');
    await (await foreground.database).execute(
        "CREATE TRIGGER fail_change BEFORE INSERT ON schedule_changes BEGIN SELECT RAISE(ABORT, 'test failure'); END");
    await expectLater(
        foreground.saveScheduleEntries([_entry('B')], '1',
            changes: [_change('A → B')]),
        throwsA(isA<DatabaseException>()));
    expect((await foreground.getEntriesForGroup('1')).single.room, 'A');
    expect(await foreground.getPendingScheduleChanges(), isEmpty);
  });
}
