// lib/data/datasources/schedule_parser.dart

import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;
import '../../domain/entities/schedule_entry.dart';
import 'dart:convert';

class ScheduleParser {
  static const _languagePlaceholderSubjects = ['Język obcy 1'];
  static const _languagePlaceholderRooms = ['Wybierz swoją grupę językową'];

  List<ScheduleEntry> parse(
    String htmlContent,
    String groupId,
    GroupType groupType,
  ) {
    final document = html_parser.parse(htmlContent);
    final table = document.querySelector('table.zajecia') ??
        document.querySelector('table');

    if (table == null) return [];

    final rows = table.querySelectorAll('tr');
    if (rows.isEmpty) return [];

    final entries = <ScheduleEntry>[];
    int rowIndex = 0;

    // Skip header row
    if (rows.isNotEmpty && _isHeaderRow(rows[0])) {
      rowIndex = 1;
    }

    while (rowIndex < rows.length) {
      final row = rows[rowIndex];
      final cells = row.querySelectorAll('td');

      if (cells.length < 6) {
        rowIndex++;
        continue;
      }

      final termDate = _extractText(cells[0]).trim();
      final dayTime = _extractText(cells[1]).trim();
      final subject = _extractText(cells[2]).trim();
      final classType = _extractText(cells[3]).trim();
      final lecturer = _extractLecturerText(cells[4]);
      final room = _extractText(cells[5]).trim();

      // Skip empty rows
      if (termDate.isEmpty && subject.isEmpty) {
        rowIndex++;
        continue;
      }

      // Skip language placeholder rows
      if (_isLanguagePlaceholder(subject, room)) {
        rowIndex++;
        continue;
      }

      // Skip reservation if needed (handled by filter)
      final parsedTime = _parseTimeColumn(dayTime);
      final parsedDate = _parseDate(termDate);

      if (parsedDate == null) {
        rowIndex++;
        continue;
      }

      // Check if this is a moved class
      if (classType.toLowerCase().contains('przeniesienie')) {
        final movedEntry = _parseMovedClass(
          rows,
          rowIndex,
          cells,
          termDate,
          dayTime,
          subject,
          classType,
          lecturer,
          room,
          groupId,
          groupType,
          parsedDate,
          parsedTime,
        );
        if (movedEntry != null) {
          entries.addAll(movedEntry.entries);
          rowIndex += movedEntry.rowsConsumed;
          continue;
        }
      }

      // Normal entry
      final entry = ScheduleEntry(
        id: _generateId(
            groupId, termDate, subject, parsedTime?.startTime ?? ''),
        subject: subject,
        classType: classType,
        lecturer: lecturer,
        room: room,
        date: parsedDate,
        startTime: parsedTime?.startTime ?? '',
        endTime: parsedTime?.endTime ?? '',
        weekday: parsedTime?.weekday ?? '',
        durationHours: parsedTime?.durationHours ?? 0,
        groupId: groupId,
        groupType: groupType,
      );

      entries.add(entry);
      rowIndex++;
    }

    return _inferMissingExamSubjects(entries);
  }

  bool _isHeaderRow(dom.Element row) {
    return row.querySelectorAll('th').isNotEmpty;
  }

  bool _isLanguagePlaceholder(String subject, String room) {
    for (final s in _languagePlaceholderSubjects) {
      if (subject.contains(s)) return true;
    }
    for (final r in _languagePlaceholderRooms) {
      if (room.contains(r)) return true;
    }
    return false;
  }

  String _extractText(dom.Element cell) {
    // Remove all child elements (images, icons) and get only text
    final buffer = StringBuffer();
    for (final node in cell.nodes) {
      if (node.nodeType == dom.Node.TEXT_NODE) {
        buffer.write(node.text ?? '');
      } else if (node.nodeType == dom.Node.ELEMENT_NODE) {
        final el = node as dom.Element;
        // Skip img tags
        if (el.localName != 'img') {
          buffer.write(_extractText(el));
        }
      }
    }
    return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _extractLecturerText(dom.Element cell) {
    return _extractText(cell).trim();
  }

  _MovedClassResult? _parseMovedClass(
    List<dom.Element> rows,
    int rowIndex,
    List<dom.Element> cells,
    String termDate,
    String dayTime,
    String subject,
    String classType,
    String lecturer,
    String room,
    String groupId,
    GroupType groupType,
    DateTime originalDate,
    _ParsedTime? parsedTime,
  ) {
    int rowsConsumed = 1;
    final moveTextParts = <String>[classType, room, subject, dayTime];

    // UEK sometimes puts the new date in a small annotation row after the
    // moved class. Do not use the next full schedule row as the new date/time:
    // it can be a different class with a similar subject.
    for (int i = rowIndex + 1; i < rows.length && i <= rowIndex + 3; i++) {
      final nextCells = rows[i].querySelectorAll('td');
      if (nextCells.length >= 6) break;

      final text = _normalizeText(rows[i].text);
      if (text.isEmpty) {
        rowsConsumed = i - rowIndex + 1;
        continue;
      }

      moveTextParts.add(text);
      rowsConsumed = i - rowIndex + 1;
      if (!_looksLikeMoveAnnotation(text)) break;
    }

    final target = _parseMoveTarget(
      _normalizeText(moveTextParts.join(' ')),
      originalDate,
    );

    final movedEntry = ScheduleEntry(
      id: _generateId(
          groupId, termDate, subject, '${parsedTime?.startTime ?? ''}_moved'),
      subject: subject,
      classType: classType,
      lecturer: lecturer,
      room: room,
      date: originalDate,
      startTime: parsedTime?.startTime ?? '',
      endTime: parsedTime?.endTime ?? '',
      weekday: parsedTime?.weekday ?? '',
      durationHours: parsedTime?.durationHours ?? 0,
      groupId: groupId,
      groupType: groupType,
      isMoved: true,
      originalDate: originalDate,
      originalStartTime: parsedTime?.startTime,
      originalEndTime: parsedTime?.endTime,
      newDate: target?.date,
      newStartTime: target?.startTime,
      newEndTime: target?.endTime,
    );

    return _MovedClassResult(
      entries: [movedEntry],
      rowsConsumed: rowsConsumed,
    );
  }

  bool _looksLikeMoveAnnotation(String text) {
    final lower = text.toLowerCase();
    return lower.contains('przenies') ||
        lower.contains(' na ') ||
        RegExp(r'\bna\s+\d{1,2}[.]\d{1,2}').hasMatch(lower);
  }

  _MoveTarget? _parseMoveTarget(String text, DateTime originalDate) {
    final dateMatch = RegExp(
      r'\bna\s+(\d{1,2})[.](\d{1,2})(?:[.](\d{2,4}))?',
      caseSensitive: false,
    ).firstMatch(text);
    if (dateMatch == null) return null;

    final day = int.tryParse(dateMatch.group(1)!);
    final month = int.tryParse(dateMatch.group(2)!);
    if (day == null || month == null) return null;

    var year = originalDate.year;
    final yearText = dateMatch.group(3);
    if (yearText != null && yearText.isNotEmpty) {
      year = int.parse(yearText);
      if (year < 100) year += 2000;
    }

    var date = DateTime(year, month, day);
    if (yearText == null && date.isBefore(originalDate)) {
      date = DateTime(year + 1, month, day);
    }

    final afterDate = text.substring(dateMatch.end);
    final timeMatch = RegExp(
      r'(\d{1,2}:\d{2})\s*(?:-|–|—)\s*(\d{1,2}:\d{2})',
    ).firstMatch(afterDate);

    if (timeMatch == null) {
      final singleTimeMatch = RegExp(
        r'(?:godz[.]?|o|od)\s*(\d{1,2}:\d{2})',
        caseSensitive: false,
      ).firstMatch(afterDate);
      return _MoveTarget(
        date: date,
        startTime: singleTimeMatch?.group(1),
      );
    }

    return _MoveTarget(
      date: date,
      startTime: timeMatch.group(1),
      endTime: timeMatch.group(2),
    );
  }

  String _normalizeText(String value) =>
      value.replaceAll(RegExp(r'\s+'), ' ').trim();

  List<ScheduleEntry> _inferMissingExamSubjects(List<ScheduleEntry> entries) {
    final subjectsByLecturer = <String, Set<String>>{};

    for (final entry in entries) {
      final lecturerKey = _normalizeLecturer(entry.lecturer);
      if (lecturerKey.isEmpty || _isGenericSubject(entry.subject)) continue;

      subjectsByLecturer
          .putIfAbsent(lecturerKey, () => <String>{})
          .add(entry.subject.trim());
    }

    if (subjectsByLecturer.isEmpty) return entries;

    return entries.map((entry) {
      if (!_needsSubjectInference(entry)) return entry;

      final lecturerKey = _normalizeLecturer(entry.lecturer);
      final subjects = subjectsByLecturer[lecturerKey];
      if (subjects == null || subjects.length != 1) return entry;

      return entry.copyWith(subject: subjects.single);
    }).toList();
  }

  bool _needsSubjectInference(ScheduleEntry entry) {
    if (!_isGenericSubject(entry.subject)) return false;
    if (entry.lecturer.trim().isEmpty) return false;

    final classType = entry.classType.toLowerCase();
    return classType.contains('egzamin') ||
        classType.contains('zaliczenie') ||
        entry.subject.trim().isEmpty;
  }

  bool _isGenericSubject(String subject) {
    final normalized = _normalizeText(subject).toLowerCase();
    if (normalized.isEmpty) return true;

    const genericSubjects = {
      'egzamin',
      'egzamin pisemny',
      'egzamin ustny',
      'zaliczenie',
      'kolokwium',
      'test',
    };

    return genericSubjects.contains(normalized);
  }

  String _normalizeLecturer(String lecturer) {
    var normalized = _normalizeText(lecturer).toLowerCase();
    if (normalized.isEmpty) return '';

    normalized = normalized.replaceAll(RegExp(r'[,.]'), ' ');
    normalized = normalized.replaceAll(
      RegExp(
        r'\b(prof|uek|dr|hab|inż|inz|mgr|lic|doc|nzw|nadzw|phd)\b',
        caseSensitive: false,
      ),
      ' ',
    );
    return _normalizeText(normalized);
  }

  DateTime? _parseDate(String dateStr) {
    // Format: 2026-02-25
    final trimmed = dateStr.trim();
    if (trimmed.isEmpty) return null;
    final match = RegExp(r'(\d{4})-(\d{2})-(\d{2})').firstMatch(trimmed);
    if (match != null) {
      return DateTime(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
      );
    }
    return null;
  }

  _ParsedTime? _parseTimeColumn(String timeStr) {
    // Format: Śr 16:45 - 18:15 (2g.)
    final trimmed = timeStr.trim();
    if (trimmed.isEmpty) return null;

    final match = RegExp(
      r'(\S+)\s+(\d{1,2}:\d{2})\s*-\s*(\d{1,2}:\d{2})\s*\((\d+(?:[.,]\d+)?)g\.\)',
    ).firstMatch(trimmed);

    if (match != null) {
      final weekday = match.group(1)!;
      final startTime = match.group(2)!;
      final endTime = match.group(3)!;
      final durationStr = match.group(4)!.replaceAll(',', '.');
      final duration = double.tryParse(durationStr) ?? 0.0;

      return _ParsedTime(
        weekday: weekday,
        startTime: startTime,
        endTime: endTime,
        durationHours: duration,
      );
    }

    // Fallback: try to extract times only
    final fallback =
        RegExp(r'(\d{1,2}:\d{2})\s*-\s*(\d{1,2}:\d{2})').firstMatch(trimmed);
    if (fallback != null) {
      return _ParsedTime(
        weekday: '',
        startTime: fallback.group(1)!,
        endTime: fallback.group(2)!,
        durationHours: 0,
      );
    }

    return null;
  }

  String _generateId(String groupId, String date, String subject, String time) {
    final raw = '$groupId|$date|$subject|$time';
    return base64Url.encode(utf8.encode(raw)).replaceAll('=', '');
  }
}

class _ParsedTime {
  final String weekday;
  final String startTime;
  final String endTime;
  final double durationHours;

  _ParsedTime({
    required this.weekday,
    required this.startTime,
    required this.endTime,
    required this.durationHours,
  });
}

class _MoveTarget {
  final DateTime date;
  final String? startTime;
  final String? endTime;

  _MoveTarget({
    required this.date,
    this.startTime,
    this.endTime,
  });
}

class _MovedClassResult {
  final List<ScheduleEntry> entries;
  final int rowsConsumed;

  _MovedClassResult({required this.entries, required this.rowsConsumed});
}
