// lib/data/datasources/local_database.dart

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;
import '../../domain/entities/group.dart';
import '../../domain/entities/schedule_entry.dart';
import '../../domain/entities/schedule_change.dart';
import '../../domain/entities/subject_filter.dart';
import '../../domain/entities/user_event.dart';

class LocalDatabase {
  LocalDatabase({DatabaseFactory? factory}) : _factory = factory;

  final DatabaseFactory? _factory;
  Future<Database>? _database;
  Future<void>? _closing;
  static const _dbName = 'plan_zajec.db';
  static const _dbVersion = 4;

  Future<Database> get database async {
    while (true) {
      while (_closing != null) {
        await _closing;
      }
      final pending = _database ??= _openDatabase();
      final db = await pending;
      if (identical(_database, pending) && db.isOpen) return db;
      if (identical(_database, pending)) _database = null;
    }
  }

  Future<Database> _openDatabase() async {
    try {
      return await _initDatabase();
    } catch (_) {
      _database = null;
      rethrow;
    }
  }

  Future<Database> _initDatabase() async {
    final factory = _factory ?? databaseFactory;
    final dbPath = await factory.getDatabasesPath();
    final dbFile = path.join(dbPath, _dbName);

    return factory.openDatabase(
      dbFile,
      options: OpenDatabaseOptions(
        version: _dbVersion,
        // The background engine must not close the foreground engine's handle.
        singleInstance: false,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await _createScheduleChanges(db);
    await db.execute('''
      CREATE TABLE groups (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        group_id TEXT NOT NULL UNIQUE,
        group_type TEXT NOT NULL,
        name TEXT,
        is_enabled INTEGER NOT NULL DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE schedule_entries (
        id TEXT PRIMARY KEY,
        subject TEXT NOT NULL,
        class_type TEXT NOT NULL,
        lecturer TEXT NOT NULL,
        room TEXT NOT NULL,
        date TEXT NOT NULL,
        start_time TEXT NOT NULL,
        end_time TEXT NOT NULL,
        weekday TEXT NOT NULL,
        duration_hours REAL NOT NULL,
        group_id TEXT NOT NULL,
        group_type TEXT NOT NULL,
        is_moved INTEGER NOT NULL DEFAULT 0,
        original_date TEXT,
        original_start_time TEXT,
        original_end_time TEXT,
        new_date TEXT,
        new_start_time TEXT,
        new_end_time TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE user_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        event_type TEXT NOT NULL DEFAULT 'Wydarzenie',
        description TEXT,
        date TEXT NOT NULL,
        start_time TEXT NOT NULL,
        end_time TEXT NOT NULL,
        room TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE subject_filters (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        subject TEXT NOT NULL,
        group_id TEXT NOT NULL,
        is_hidden INTEGER NOT NULL DEFAULT 1,
        UNIQUE(subject, group_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 4) await _createScheduleChanges(db);
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS app_settings (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 3) {
      await db.execute('''
        ALTER TABLE user_events
        ADD COLUMN event_type TEXT NOT NULL DEFAULT 'Wydarzenie'
      ''');
    }
  }

  // ========== GROUPS ==========

  Future<List<Group>> getAllGroups() async {
    final db = await database;
    final maps = await db.query('groups', orderBy: 'id ASC');
    return maps.map(_groupFromMap).toList();
  }

  Future<void> insertGroup(Group group) async {
    final db = await database;
    await db.insert(
      'groups',
      _groupToMap(group),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateGroup(Group group) async {
    final db = await database;
    await db.update(
      'groups',
      _groupToMap(group),
      where: 'group_id = ?',
      whereArgs: [group.groupId],
    );
  }

  Future<void> deleteGroup(String groupId) async {
    final db = await database;
    await db.transaction((txn) async {
      for (final table in [
        'groups',
        'schedule_entries',
        'subject_filters',
        'schedule_changes'
      ]) {
        await txn.delete(table, where: 'group_id = ?', whereArgs: [groupId]);
      }
      await txn.delete('app_settings',
          where: 'key = ?', whereArgs: ['schedule_period_$groupId']);
    });
  }

  Map<String, dynamic> _groupToMap(Group g) => {
        'group_id': g.groupId,
        'group_type': g.groupType.dbValue,
        'name': g.name,
        'is_enabled': g.isEnabled ? 1 : 0,
      };

  Group _groupFromMap(Map<String, dynamic> m) => Group(
        id: m['id'] as int?,
        groupId: m['group_id'] as String,
        groupType: GroupTypeExtension.fromString(m['group_type'] as String),
        name: m['name'] as String?,
        isEnabled: (m['is_enabled'] as int) == 1,
      );

  // ========== SCHEDULE ENTRIES ==========

  Future<void> saveScheduleEntries(List<ScheduleEntry> entries, String groupId,
      {List<ScheduleChange> changes = const [], int? period}) async {
    final db = await database;
    final batch = db.batch();

    // Delete existing entries for this group
    batch.delete('schedule_entries',
        where: 'group_id = ?', whereArgs: [groupId]);

    for (final entry in entries) {
      batch.insert(
        'schedule_entries',
        _entryToMap(entry),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    for (final change in changes) {
      batch.insert('schedule_changes', change.toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    if (period != null) {
      batch.insert('app_settings',
          {'key': 'schedule_period_$groupId', 'value': '$period'},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }

    await batch.commit(noResult: true);
  }

  Future<void> _createScheduleChanges(Database db) => db.execute('''
    CREATE TABLE schedule_changes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      change_key TEXT NOT NULL UNIQUE,
      group_id TEXT NOT NULL,
      subject TEXT NOT NULL,
      description TEXT NOT NULL,
      detected_at TEXT NOT NULL
    )
  ''');

  Future<List<ScheduleChange>> getPendingScheduleChanges() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT c.* FROM schedule_changes c
      INNER JOIN groups g ON c.group_id = g.group_id
      WHERE g.is_enabled = 1 AND NOT EXISTS (
        SELECT 1 FROM subject_filters f WHERE f.group_id = c.group_id
        AND f.subject = c.subject AND f.is_hidden = 1
      ) ORDER BY c.id ASC LIMIT 100
    ''');
    return rows.map(ScheduleChange.fromMap).toList();
  }

  Future<void> acknowledgeScheduleChanges(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    await db.delete('schedule_changes',
        where: 'id IN (${List.filled(ids.length, '?').join(',')})',
        whereArgs: ids);
  }

  Future<List<ScheduleEntry>> getEntriesForGroup(String groupId) async {
    final db = await database;
    final maps = await db.query('schedule_entries',
        where: 'group_id = ?',
        whereArgs: [groupId],
        orderBy: 'date ASC, start_time ASC');
    return maps.map(_entryFromMap).toList();
  }

  Future<List<ScheduleEntry>> getSavedEntries() async {
    final db = await database;
    final maps =
        await db.query('schedule_entries', orderBy: 'date ASC, start_time ASC');
    return maps.map(_entryFromMap).toList();
  }

  Future<List<ScheduleEntry>> getEntriesForDate(DateTime date) async {
    final db = await database;
    final dateStr = _formatDate(date);
    final maps = await db.query(
      'schedule_entries',
      where: 'date = ?',
      whereArgs: [dateStr],
      orderBy: 'start_time ASC',
    );
    return maps.map(_entryFromMap).toList();
  }

  Map<String, dynamic> _entryToMap(ScheduleEntry e) => {
        'id': e.id,
        'subject': e.subject,
        'class_type': e.classType,
        'lecturer': e.lecturer,
        'room': e.room,
        'date': _formatDate(e.date),
        'start_time': e.startTime,
        'end_time': e.endTime,
        'weekday': e.weekday,
        'duration_hours': e.durationHours,
        'group_id': e.groupId,
        'group_type': e.groupType.dbValue,
        'is_moved': e.isMoved ? 1 : 0,
        'original_date':
            e.originalDate != null ? _formatDate(e.originalDate!) : null,
        'original_start_time': e.originalStartTime,
        'original_end_time': e.originalEndTime,
        'new_date': e.newDate != null ? _formatDate(e.newDate!) : null,
        'new_start_time': e.newStartTime,
        'new_end_time': e.newEndTime,
      };

  ScheduleEntry _entryFromMap(Map<String, dynamic> m) => ScheduleEntry(
        id: m['id'] as String,
        subject: m['subject'] as String,
        classType: m['class_type'] as String,
        lecturer: m['lecturer'] as String,
        room: m['room'] as String,
        date: DateTime.parse(m['date'] as String),
        startTime: m['start_time'] as String,
        endTime: m['end_time'] as String,
        weekday: m['weekday'] as String,
        durationHours: (m['duration_hours'] as num).toDouble(),
        groupId: m['group_id'] as String,
        groupType: GroupTypeExtension.fromString(m['group_type'] as String),
        isMoved: (m['is_moved'] as int) == 1,
        originalDate: m['original_date'] != null
            ? DateTime.tryParse(m['original_date'] as String)
            : null,
        originalStartTime: m['original_start_time'] as String?,
        originalEndTime: m['original_end_time'] as String?,
        newDate: m['new_date'] != null
            ? DateTime.tryParse(m['new_date'] as String)
            : null,
        newStartTime: m['new_start_time'] as String?,
        newEndTime: m['new_end_time'] as String?,
      );

  // ========== USER EVENTS ==========

  Future<List<UserEvent>> getAllUserEvents() async {
    final db = await database;
    final maps =
        await db.query('user_events', orderBy: 'date ASC, start_time ASC');
    return maps.map(_eventFromMap).toList();
  }

  Future<void> insertUserEvent(UserEvent event) async {
    final db = await database;
    await db.insert('user_events', _eventToMap(event));
  }

  Future<void> updateUserEvent(UserEvent event) async {
    final db = await database;
    await db.update(
      'user_events',
      _eventToMap(event),
      where: 'id = ?',
      whereArgs: [event.id],
    );
  }

  Future<void> deleteUserEvent(int id) async {
    final db = await database;
    await db.delete('user_events', where: 'id = ?', whereArgs: [id]);
  }

  Map<String, dynamic> _eventToMap(UserEvent e) => {
        if (e.id != null) 'id': e.id,
        'title': e.title,
        'event_type': e.eventType,
        'description': e.description,
        'date': _formatDate(e.date),
        'start_time': e.startTime,
        'end_time': e.endTime,
        'room': e.room,
      };

  UserEvent _eventFromMap(Map<String, dynamic> m) => UserEvent(
        id: m['id'] as int?,
        title: m['title'] as String,
        eventType: _eventTypeFromMap(m),
        description: m['description'] as String?,
        date: DateTime.parse(m['date'] as String),
        startTime: m['start_time'] as String,
        endTime: m['end_time'] as String,
        room: m['room'] as String?,
      );

  String _eventTypeFromMap(Map<String, dynamic> m) {
    final raw = m['event_type'] as String?;
    if (raw == null || raw.trim().isEmpty) {
      return UserEvent.defaultEventType;
    }
    return raw.trim();
  }

  // ========== SUBJECT FILTERS ==========

  Future<List<SubjectFilter>> getAllSubjectFilters() async {
    final db = await database;
    final maps = await db.query('subject_filters');
    return maps.map(_filterFromMap).toList();
  }

  Future<void> upsertSubjectFilter(SubjectFilter filter) async {
    final db = await database;
    await db.insert(
      'subject_filters',
      {
        'subject': filter.subject,
        'group_id': filter.groupId,
        'is_hidden': filter.isHidden ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteSubjectFilter(int id) async {
    final db = await database;
    await db.delete('subject_filters', where: 'id = ?', whereArgs: [id]);
  }

  SubjectFilter _filterFromMap(Map<String, dynamic> m) => SubjectFilter(
        id: m['id'] as int?,
        subject: m['subject'] as String,
        groupId: m['group_id'] as String,
        isHidden: (m['is_hidden'] as int) == 1,
      );

  // ========== SETTINGS ==========

  Future<String?> getSetting(String key) async {
    final db = await database;
    final maps = await db.query('app_settings',
        where: 'key = ?', whereArgs: [key], limit: 1);
    if (maps.isEmpty) return null;
    return maps.first['value'] as String?;
  }

  Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert(
      'app_settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  String _formatDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<void> close() {
    if (_closing != null) return _closing!;
    final pending = _database;
    if (pending == null) return Future.value();
    _database = null;
    return _closing = _closeDatabase(pending);
  }

  Future<void> _closeDatabase(Future<Database> pending) async {
    try {
      final db = await pending;
      await db.close();
    } finally {
      _closing = null;
    }
  }
}
