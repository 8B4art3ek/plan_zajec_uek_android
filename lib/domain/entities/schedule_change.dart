import 'schedule_entry.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';

class ScheduleChange {
  const ScheduleChange(
      {this.id,
      required this.groupId,
      required this.subject,
      required this.description,
      required this.detectedAt});
  final int? id;
  final String groupId;
  final String subject;
  final String description;
  final DateTime detectedAt;

  Map<String, Object?> toMap() => {
        'change_key': sha256
            .convert(utf8.encode(jsonEncode([groupId, subject, description])))
            .toString(),
        'group_id': groupId,
        'subject': subject,
        'description': description,
        'detected_at': detectedAt.toIso8601String(),
      };

  factory ScheduleChange.fromMap(Map<String, Object?> row) => ScheduleChange(
        id: row['id'] as int,
        groupId: row['group_id'] as String,
        subject: row['subject'] as String,
        description: row['description'] as String,
        detectedAt: DateTime.parse(row['detected_at'] as String),
      );

  static List<ScheduleChange> compare(
      List<ScheduleEntry> before, List<ScheduleEntry> after, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final old = {for (final entry in before) entry.id: entry};
    final added = <ScheduleEntry>[];
    final handled = <String>{};
    final changes = <ScheduleChange>[];
    void record(ScheduleEntry entry, String message) {
      if (entry.date.isBefore(today) &&
          (entry.newDate == null || entry.newDate!.isBefore(today))) {
        return;
      }
      changes.add(ScheduleChange(
          groupId: entry.groupId,
          subject: entry.subject,
          description: message,
          detectedAt: now));
    }

    ScheduleEntry? destination(
        ScheduleEntry moved, Iterable<ScheduleEntry> entries) {
      if (moved.newDate == null) return null;
      final source = entries.toList();
      final markers = source
          .where((entry) =>
              entry.isMoved &&
              entry.groupId == moved.groupId &&
              entry.subject == moved.subject &&
              entry.newDate == moved.newDate &&
              (entry.newStartTime == null ||
                  moved.newStartTime == null ||
                  entry.newStartTime == moved.newStartTime))
          .length;
      if (markers > 1) return null;
      final matches = source
          .where((entry) =>
              !entry.isMoved &&
              entry.groupId == moved.groupId &&
              entry.subject == moved.subject &&
              entry.date == moved.newDate &&
              (moved.newStartTime == null ||
                  entry.startTime == moved.newStartTime))
          .toList();
      return matches.length == 1 ? matches.single : null;
    }

    // UEK changes the original row's ID/type when it becomes a move marker.
    // Match that marker before ordinary additions and consume its destination once.
    for (final moved in after.where((entry) => entry.isMoved)) {
      final originDate = moved.originalDate ?? moved.date;
      final originTime = moved.originalStartTime ?? moved.startTime;
      final origins = old.values
          .where((entry) =>
              !entry.isMoved &&
              entry.groupId == moved.groupId &&
              entry.subject == moved.subject &&
              entry.date == originDate &&
              entry.startTime == originTime)
          .toList();
      final previous =
          old[moved.id] ?? (origins.length == 1 ? origins.single : null);
      final candidate = destination(moved, after);
      final target = candidate != null && !handled.contains(candidate.id)
          ? candidate
          : null;
      final oldTarget =
          previous?.isMoved == true ? destination(previous!, before) : null;
      final existingTarget = target == null ? null : old[target.id];
      if (previous != null) old.remove(previous.id);
      if (oldTarget != null) old.remove(oldTarget.id);
      if (target != null) {
        old.remove(target.id);
        handled.add(target.id);
      }
      handled.add(moved.id);
      final changed = previous == null ||
          _details(previous) != _details(moved) ||
          (target != null &&
              oldTarget != null &&
              _details(target) != _details(oldTarget)) ||
          (previous.isMoved &&
              target != null &&
              oldTarget == null &&
              existingTarget == null) ||
          (previous.isMoved && target == null && oldTarget != null);
      if (changed) {
        final original = oldTarget ??
            previous ??
            moved.copyWith(
                isMoved: false, classType: '', room: '', lecturer: '');
        record(target ?? moved,
            'Zmieniono zajęcia\nPrzed: ${_details(original)}\nTeraz: ${_details(target ?? moved)}');
      }
    }

    for (final entry in after.where((entry) => !handled.contains(entry.id))) {
      final previous = old.remove(entry.id);
      if (previous == null) {
        added.add(entry);
        continue;
      }
      if (_details(previous) != _details(entry)) {
        record(entry,
            'Zmieniono zajęcia\nPrzed: ${_details(previous)}\nTeraz: ${_details(entry)}');
      }
    }
    for (final entry in added) {
      final matches = old.values
          .where((previous) =>
              previous.subject == entry.subject &&
              previous.date == entry.date &&
              previous.classType == entry.classType)
          .toList();
      final candidates = added
          .where((other) =>
              other.subject == entry.subject &&
              other.date == entry.date &&
              other.classType == entry.classType)
          .length;
      if (matches.length == 1 && candidates == 1) {
        final previous = old.remove(matches.single.id)!;
        record(entry,
            'Zmieniono zajęcia\nPrzed: ${_details(previous)}\nTeraz: ${_details(entry)}');
      } else {
        record(entry, 'Dodano zajęcia\n${_details(entry)}');
      }
    }
    for (final entry in old.values) {
      record(entry, 'Usunięto z planu\n${_details(entry)}');
    }
    return changes;
  }

  static String _details(ScheduleEntry entry) {
    String date(DateTime value) =>
        '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year}';
    return [
      entry.subject,
      date(entry.date),
      '${entry.startTime}–${entry.endTime}',
      if (entry.classType.isNotEmpty) entry.classType,
      if (entry.room.isNotEmpty) entry.room,
      if (entry.lecturer.isNotEmpty) entry.lecturer,
      if (entry.isMoved)
        'Przeniesione${entry.newDate == null ? '' : ': ${date(entry.newDate!)} ${entry.newStartTime ?? ''}${entry.newEndTime == null ? '' : '–${entry.newEndTime}'}'}',
    ].join(' · ');
  }
}
