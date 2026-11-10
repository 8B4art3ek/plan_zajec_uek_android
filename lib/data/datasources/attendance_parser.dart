import 'dart:convert';

class AttendanceSnapshot {
  const AttendanceSnapshot({
    required this.pageTitle,
    required this.requiresLogin,
    required this.headers,
    required this.rows,
    this.pageUrl = '',
    this.documentId = '',
    this.isReady = true,
    this.isEmpty = false,
    this.nextPageUrl,
  });

  final String pageTitle;
  final bool requiresLogin;
  final List<String> headers;
  final List<List<String>> rows;
  final String pageUrl;
  final String documentId;
  final bool isReady;
  final bool isEmpty;
  final String? nextPageUrl;

  bool get hasRows => rows.isNotEmpty;

  bool get hasAttendanceTable =>
      headers.any((header) =>
          header.toLowerCase().contains('identyfikator') ||
          header.toLowerCase().contains('przedmiot')) &&
      headers.any((header) => header.toLowerCase().contains('status'));

  List<AttendanceSubject> get subjects {
    return _groupSubjects(
        rows.map((row) => AttendanceRecord.fromRow(headers, row)));
  }

  List<AttendanceSemester> get semesters {
    final grouped = <String?, List<AttendanceRecord>>{};
    for (final row in rows) {
      final record = AttendanceRecord.fromRow(headers, row);
      grouped.putIfAbsent(record.semesterCode, () => []).add(record);
    }
    final result = grouped.entries
        .map((entry) => AttendanceSemester(
              code: entry.key,
              subjects: _groupSubjects(entry.value),
            ))
        .toList();
    result.sort((a, b) {
      if (a.code == null) return b.code == null ? 0 : 1;
      if (b.code == null) return -1;
      final yearOrder =
          b.code!.substring(0, 4).compareTo(a.code!.substring(0, 4));
      if (yearOrder != 0) return yearOrder;
      return a.code!.endsWith('L') ? -1 : 1;
    });
    return result;
  }

  static List<AttendanceSubject> _groupSubjects(
      Iterable<AttendanceRecord> records) {
    final grouped = <String, List<AttendanceRecord>>{};
    for (final record in records) {
      grouped.putIfAbsent(record.subjectName, () => []).add(record);
    }
    return grouped.entries
        .map((entry) => AttendanceSubject(
              name: entry.key,
              records: entry.value,
            ))
        .toList(growable: false);
  }
}

class AttendanceSemester {
  const AttendanceSemester({required this.code, required this.subjects});

  final String? code;
  final List<AttendanceSubject> subjects;

  String get label {
    final value = code;
    if (value == null) return 'Bez oznaczenia semestru';
    return 'Semestr ${value.endsWith('Z') ? 'zimowy' : 'letni'} ${value.substring(0, 9)}';
  }
}

class AttendanceSubject {
  const AttendanceSubject({required this.name, required this.records});

  final String name;
  final List<AttendanceRecord> records;

  int get registeredCount =>
      records.where((record) => record.isRegistered).length;
}

class AttendanceRecord {
  const AttendanceRecord({
    required this.subjectName,
    required this.classType,
    required this.classDetails,
    required this.openedAt,
    required this.registeredAt,
    required this.status,
    this.semesterCode,
  });

  final String subjectName;
  final String classType;
  final String classDetails;
  final String openedAt;
  final String registeredAt;
  final String status;
  final String? semesterCode;

  bool get isRegistered => status.toLowerCase().contains('zarejestrowano');

  factory AttendanceRecord.fromRow(List<String> headers, List<String> row) {
    final subject = _valueFor(headers, row, ['identyfikator', 'przedmiot']);
    final subjectParts = subject
        .split('\n')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    final titleAndClass = subjectParts.join(' ');
    final classMatch = RegExp(
      r',\s*([^,]+),\s*grupa\s*(\d+)',
      caseSensitive: false,
    ).firstMatch(titleAndClass);
    final subjectName = classMatch == null
        ? (subjectParts.isEmpty ? 'Nieznany przedmiot' : subjectParts.first)
        : titleAndClass.substring(0, classMatch.start).trim();
    final classDetails = classMatch == null
        ? subjectParts.skip(1).join(' ')
        : '${classMatch.group(1)}, grupa ${classMatch.group(2)}${titleAndClass.substring(classMatch.end).trim().isEmpty ? '' : ' · ${titleAndClass.substring(classMatch.end).trim()}'}';

    return AttendanceRecord(
      subjectName: subjectName,
      classType: classMatch?.group(1)?.trim() ?? '',
      classDetails: classDetails,
      openedAt: _valueFor(headers, row, ['termin otwarcia']),
      registeredAt: _valueFor(headers, row, ['data rejestracji']),
      status: _valueFor(headers, row, ['status']),
      semesterCode: _semesterCode(titleAndClass),
    );
  }

  static String? _semesterCode(String identifier) {
    final match = RegExp(
      r'(?<![\w/])(\d{4}|\d{2})\s*/\s*(\d{4}|\d{2})\s*([ZL])(?!\w)',
      caseSensitive: false,
    ).firstMatch(identifier);
    if (match == null) return null;
    int year(String value) =>
        value.length == 2 ? 2000 + int.parse(value) : int.parse(value);
    final start = year(match.group(1)!);
    final end = year(match.group(2)!);
    if (end != start + 1) return null;
    return '$start/$end${match.group(3)!.toUpperCase()}';
  }

  static String _valueFor(
    List<String> headers,
    List<String> row,
    List<String> headerParts,
  ) {
    final index = headers.indexWhere((header) {
      final normalized = header.toLowerCase();
      return headerParts.any(normalized.contains);
    });
    return index >= 0 && index < row.length ? row[index] : '';
  }
}

class AttendanceParser {
  const AttendanceParser();

  AttendanceSnapshot parseWebViewResult(Object value) {
    final data = _decodeMap(value);
    final headers = _strings(data['headers']);
    final rows = _rows(data['rows']);

    return AttendanceSnapshot(
      pageTitle: (data['title'] as String? ?? '').trim(),
      requiresLogin: data['isLogin'] == true,
      headers: headers,
      rows: rows,
      pageUrl: data['url'] as String? ?? '',
      documentId: data['documentId']?.toString() ?? '',
      isReady: data['isReady'] != false,
      isEmpty: data['isEmpty'] == true,
      nextPageUrl: data['nextPageUrl'] is String &&
              (data['nextPageUrl'] as String).trim().isNotEmpty
          ? (data['nextPageUrl'] as String).trim()
          : null,
    );
  }

  Map<String, dynamic> _decodeMap(Object value) {
    Object decoded = value;
    if (decoded is String) {
      decoded = jsonDecode(decoded);
      if (decoded is String) decoded = jsonDecode(decoded);
    }
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return decoded.cast<String, dynamic>();
    throw const FormatException('Nieprawidłowy wynik z portalu UEK.');
  }

  List<String> _strings(Object? value) {
    if (value is! List) return const [];
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  List<List<String>> _rows(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<List>()
        .map((row) => row.map((cell) => cell.toString().trim()).toList())
        .where((row) => row.any((cell) => cell.isNotEmpty))
        .toList(growable: false);
  }
}

Uri? parseAttendancePageUrl(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.port != 443 ||
      uri.userInfo.isNotEmpty ||
      uri.host != 'portal.uek.krakow.pl' ||
      uri.path != '/dashboard/obecnosci/mojeObecnosci' ||
      uri.hasFragment) {
    return null;
  }
  try {
    final pages = uri.queryParametersAll['page'];
    if (pages != null &&
        (pages.length != 1 || !RegExp(r'^[1-9]\d*$').hasMatch(pages.single))) {
      return null;
    }
    return uri;
  } on ArgumentError {
    return null;
  } on FormatException {
    return null;
  }
}
