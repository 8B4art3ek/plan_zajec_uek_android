import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:plan_zajec_uek/data/datasources/local_database.dart';

class _Factory implements DatabaseFactory {
  final handles = <_Database>[];
  final settings = <String, String>{};
  final options = <OpenDatabaseOptions?>[];
  Completer<void>? opening;
  bool failNext = false;
  int attempts = 0;

  @override
  Future<String> getDatabasesPath() async => '/databases';

  @override
  Future<Database> openDatabase(String path,
      {OpenDatabaseOptions? options}) async {
    attempts++;
    this.options.add(options);
    await opening?.future;
    if (failNext) {
      failNext = false;
      throw StateError('Open failed');
    }
    if (options?.singleInstance != false) {
      for (final handle in handles) {
        if (handle.isOpen) return handle;
      }
    }
    final database = _Database(settings);
    handles.add(database);
    return database;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Database implements Database {
  _Database(this.settings);
  final Map<String, String> settings;
  bool open = true;
  Completer<void>? closing;
  int closeCount = 0;
  @override
  bool get isOpen => open;
  @override
  Future<void> close() async {
    closeCount++;
    open = false;
    await closing?.future;
  }

  @override
  Future<int> insert(String table, Map<String, Object?> values,
      {String? nullColumnHack, ConflictAlgorithm? conflictAlgorithm}) async {
    if (!open) throw StateError('database_closed');
    settings[values['key'] as String] = values['value'] as String;
    return 1;
  }

  @override
  Future<List<Map<String, Object?>>> query(String table,
      {bool? distinct,
      List<String>? columns,
      String? where,
      List<Object?>? whereArgs,
      String? groupBy,
      String? having,
      String? orderBy,
      int? limit,
      int? offset}) async {
    if (!open) throw StateError('database_closed');
    final key = whereArgs!.first as String;
    return settings.containsKey(key)
        ? [
            {'key': key, 'value': settings[key]}
          ]
        : [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('background close does not invalidate foreground handle or saved data',
      () async {
    final factory = _Factory();
    final foreground = LocalDatabase(factory: factory);
    final background = LocalDatabase(factory: factory);
    addTearDown(foreground.close);
    addTearDown(background.close);
    await foreground.setSetting('group', '123');
    final foregroundHandle = await foreground.database;
    await background.setSetting('last_refresh', 'now');
    expect(await background.database, isNot(same(foregroundHandle)));
    await background.close();
    expect(foregroundHandle.isOpen, true);
    expect(await foreground.getSetting('group'), '123');
    expect(await foreground.getSetting('last_refresh'), 'now');
    expect(factory.options.every((options) => options?.singleInstance == false),
        true);
  });

  test('simultaneous reads share one opening within an owner', () async {
    final factory = _Factory()..opening = Completer<void>();
    final db = LocalDatabase(factory: factory);
    addTearDown(db.close);
    final reads = [db.database, db.database, db.database];
    await pumpEventQueue();
    expect(factory.attempts, 1);
    factory.opening!.complete();
    final handles = await Future.wait(reads);
    expect(handles.every((handle) => identical(handle, handles.first)), true);
  });

  test('closed cached handle is reopened without losing stored settings',
      () async {
    final factory = _Factory();
    final db = LocalDatabase(factory: factory);
    addTearDown(db.close);
    await db.setSetting('theme', 'midnight');
    final previous = await db.database;
    await previous.close();
    expect(await db.getSetting('theme'), 'midnight');
    expect(await db.database, isNot(same(previous)));
  });

  test('new read waits for close and concurrent closes run only once',
      () async {
    final factory = _Factory();
    final db = LocalDatabase(factory: factory);
    addTearDown(db.close);
    final old = await db.database as _Database;
    old.closing = Completer<void>();
    final firstClose = db.close();
    expect(db.close(), same(firstClose));
    var readFinished = false;
    final read = db.database.then((value) {
      readFinished = true;
      return value;
    });
    await pumpEventQueue();
    expect(readFinished, false);
    expect(factory.attempts, 1);
    old.closing!.complete();
    await firstClose;
    expect(await read, isNot(same(old)));
    expect(old.closeCount, 1);
  });

  test('close during opening cannot return the closing handle to a reader',
      () async {
    final factory = _Factory()..opening = Completer<void>();
    final db = LocalDatabase(factory: factory);
    addTearDown(db.close);
    final read = db.database;
    await pumpEventQueue();
    final close = db.close();
    factory.opening!.complete();
    await close;
    final handle = await read;
    expect(handle.isOpen, true);
    expect(factory.handles.first.isOpen, false);
    expect(factory.handles, hasLength(2));
  });

  test('failed open can be retried', () async {
    final factory = _Factory()..failNext = true;
    final db = LocalDatabase(factory: factory);
    addTearDown(db.close);
    await expectLater(db.database, throwsStateError);
    expect((await db.database).isOpen, true);
    expect(factory.attempts, 2);
  });
}
