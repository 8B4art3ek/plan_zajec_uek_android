import 'dart:convert';

import '../../domain/entities/usos_import.dart';

class UsosImportParser {
  const UsosImportParser();

  UsosImportData parseWebViewResult(Object rawResult) {
    final payload = _decodePayload(rawResult);
    final text = (payload['text'] as String? ?? '').trim();
    final rows = (payload['rows'] as List? ?? const [])
        .whereType<String>()
        .map(_cleanup)
        .where((row) => row.isNotEmpty)
        .toList();
    final capturedDeanCodes = (payload['deanCodes'] as List? ?? const [])
        .whereType<String>()
        .map((code) => code.trim().toUpperCase())
        .where((code) => code.isNotEmpty)
        .toList();

    final sources = _buildSources(text, rows);
    return UsosImportData(
      pageUrl: payload['url'] as String?,
      pageTitle: payload['title'] as String?,
      deanCodes: capturedDeanCodes.isEmpty
          ? _extractDeanCodes(sources)
          : _uniqueBy(capturedDeanCodes, (code) => code),
      languageGroups: _extractLanguageGroups(sources),
    );
  }

  Map<String, dynamic> _decodePayload(Object rawResult) {
    Object? decoded = rawResult;
    if (rawResult is String) {
      decoded = jsonDecode(rawResult);
      if (decoded is String) decoded = jsonDecode(decoded);
    }

    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return decoded.cast<String, dynamic>();
    throw const FormatException('Nieprawidlowy wynik skanowania USOS.');
  }

  List<String> _buildSources(String text, List<String> rows) {
    final sources = <String>[...rows];
    final lines = text
        .split(RegExp(r'[\r\n]+'))
        .map(_cleanup)
        .where((line) => line.isNotEmpty && line.length <= 600)
        .toList();
    sources.addAll(lines);

    // USOS puts the language code and "grupa nr" on separate lines.
    for (var index = 0; index < lines.length; index++) {
      if (_courseCodeFromText(lines[index]) == null) continue;

      for (var nextIndex = index + 1; nextIndex < lines.length; nextIndex++) {
        if (_courseCodeFromText(lines[nextIndex]) != null) break;
        if (_groupNumberFromText(_fold(lines[nextIndex])) == null) continue;

        final joined = lines.sublist(index, nextIndex + 1).join(' ');
        if (joined.length <= 600) sources.add(joined);
        break;
      }
    }
    return _uniqueBy(sources, (source) => _fold(source));
  }

  List<String> _extractDeanCodes(List<String> sources) {
    final markedCodes = <String>[];
    final markedCodePattern = RegExp(
      r'grupa\s+dziekanska\s*:\s*(?:[a-z0-9-]+\s*)?\[([a-z0-9-]+)\]',
      caseSensitive: false,
    );

    for (final source in sources) {
      if (_courseCodeCount(source) > 1) continue;
      final folded = _fold(source);
      for (final match in markedCodePattern.allMatches(folded)) {
        markedCodes.add(match.group(1)!.toUpperCase());
      }
    }
    if (markedCodes.isNotEmpty) {
      return _uniqueBy(markedCodes, (code) => code);
    }

    final codes = <String>[];
    final codePattern = RegExp(
      r'\b[A-Z0-9]{2,10}S[12][A-Z0-9]*[-/][A-Z0-9/-]{2,}\b',
      caseSensitive: false,
    );

    for (final source in sources) {
      for (final match in codePattern.allMatches(source)) {
        final code = match.group(0)!.toUpperCase().replaceAll('/', '-');
        if (code.startsWith('CJ-')) continue;
        if (code.contains('--')) continue;
        codes.add(code);
      }
    }

    return _uniqueBy(codes, (code) => code);
  }

  List<UsosLanguageGroup> _extractLanguageGroups(List<String> sources) {
    final groups = <UsosLanguageGroup>[];

    for (final source in sources) {
      final folded = _fold(source);
      final courseCode = _courseCodeFromText(source);
      final language =
          _languageFromText(folded) ?? _languageFromCourseCode(courseCode);
      if (language == null) continue;

      final level = _levelFromText(folded) ?? _levelFromCourseCode(courseCode);
      final groupNumber = _groupNumberFromText(folded);
      if (level == null || (groupNumber == null && courseCode == null)) {
        continue;
      }

      groups.add(
        UsosLanguageGroup(
          languageName: language.name,
          languageCodeCandidates: language.codes,
          level: level,
          groupNumber: groupNumber ?? 0,
          semester:
              _semesterFromText(folded) ?? _semesterFromCourseCode(courseCode),
          studyLevel: _studyLevelFromText(folded) ??
              _studyLevelFromCourseCode(courseCode),
          usosCourseCode: courseCode,
          sourceText: source,
        ),
      );
    }

    final uniqueGroups = _uniqueBy(
      groups,
      (group) => '${group.languageCodeCandidates.join('|')}|${group.level}|'
          '${group.groupNumber}|${group.semester}|${group.studyLevel}|'
          '${group.usosCourseCode}',
    );
    final courseCodesWithGroupNumber = uniqueGroups
        .where(
            (group) => group.groupNumber != 0 && group.usosCourseCode != null)
        .map((group) => group.usosCourseCode!)
        .toSet();

    return uniqueGroups
        .where(
          (group) =>
              group.groupNumber != 0 ||
              group.usosCourseCode == null ||
              !courseCodesWithGroupNumber.contains(group.usosCourseCode),
        )
        .toList(growable: false);
  }

  _LanguageDefinition? _languageFromText(String folded) {
    for (final language in _languages) {
      if (language.terms.any((term) => folded.contains(term))) {
        return language;
      }
    }
    return null;
  }

  _LanguageDefinition? _languageFromCourseCode(String? courseCode) {
    if (courseCode == null) return null;
    final code = courseCode.split('-').last.split('.').first;
    for (final language in _languages) {
      if (language.codes.contains(code)) return language;
    }
    return null;
  }

  String? _courseCodeFromText(String source) {
    return _courseCodePattern.firstMatch(source)?.group(1)?.toUpperCase();
  }

  int _courseCodeCount(String source) =>
      _courseCodePattern.allMatches(source).length;

  static final _courseCodePattern = RegExp(
    r'\b(CJ-[A-Z0-9]+-[0-9]+/[0-9]+-[A-Z]+\.[ABC][12])\b',
    caseSensitive: false,
  );

  String? _levelFromCourseCode(String? courseCode) {
    return RegExp(r'\.([ABC][12])$').firstMatch(courseCode ?? '')?.group(1);
  }

  int? _semesterFromCourseCode(String? courseCode) {
    final match = RegExp(r'-[0-9]+/([0-9]+)-').firstMatch(courseCode ?? '');
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  String? _studyLevelFromCourseCode(String? courseCode) {
    return RegExp(r'^CJ-(S[12])-').firstMatch(courseCode ?? '')?.group(1);
  }

  String? _levelFromText(String folded) {
    final match = RegExp(r'\b([abc])\s*[-.]?\s*([12])\b').firstMatch(folded);
    if (match == null) return null;
    return '${match.group(1)!.toUpperCase()}${match.group(2)}';
  }

  int? _groupNumberFromText(String folded) {
    final match = RegExp(
      r'\b(?:grupa|gr\.?|nr grupy)\s*(?:nr\.?)?\s*:?\s*(\d{1,2})\b',
    ).firstMatch(folded);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  int? _semesterFromText(String folded) {
    final match =
        RegExp(r'\b(?:semestr|sem\.?)\s*:?\s*(\d{1,2})\b').firstMatch(folded);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  String? _studyLevelFromText(String folded) {
    if (RegExp(r'\bs\s*2\b|ii stop|drugiego stop').hasMatch(folded)) {
      return 'S2';
    }
    if (RegExp(r'\bs\s*1\b|i stop|pierwszego stop').hasMatch(folded)) {
      return 'S1';
    }
    return null;
  }

  String _cleanup(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();

  String _fold(String value) {
    return value
        .toLowerCase()
        .replaceAll('ą', 'a')
        .replaceAll('ć', 'c')
        .replaceAll('ę', 'e')
        .replaceAll('ł', 'l')
        .replaceAll('ń', 'n')
        .replaceAll('ó', 'o')
        .replaceAll('ś', 's')
        .replaceAll('ź', 'z')
        .replaceAll('ż', 'z');
  }
}

class _LanguageDefinition {
  final String name;
  final List<String> codes;
  final List<String> terms;

  const _LanguageDefinition({
    required this.name,
    required this.codes,
    required this.terms,
  });
}

const _languages = [
  _LanguageDefinition(
    name: 'angielski',
    codes: ['ANG'],
    terms: ['angielski', 'english'],
  ),
  _LanguageDefinition(
    name: 'niemiecki',
    codes: ['NIEM'],
    terms: ['niemiecki', 'german'],
  ),
  _LanguageDefinition(
    name: 'hiszpanski',
    codes: ['HISZ', 'HISZP'],
    terms: ['hiszpanski', 'spanish'],
  ),
  _LanguageDefinition(
    name: 'francuski',
    codes: ['FR', 'FRANC'],
    terms: ['francuski', 'french'],
  ),
  _LanguageDefinition(
    name: 'rosyjski',
    codes: ['ROS'],
    terms: ['rosyjski', 'russian'],
  ),
  _LanguageDefinition(
    name: 'wloski',
    codes: ['WLOS', 'WL'],
    terms: ['wloski', 'italian'],
  ),
  _LanguageDefinition(
    name: 'chinski',
    codes: ['CHIN'],
    terms: ['chinski', 'chinese'],
  ),
  _LanguageDefinition(
    name: 'ukrainski',
    codes: ['UKR'],
    terms: ['ukrainski', 'ukrainian'],
  ),
];

List<T> _uniqueBy<T>(Iterable<T> values, Object Function(T value) keyOf) {
  final keys = <Object>{};
  final result = <T>[];
  for (final value in values) {
    if (keys.add(keyOf(value))) result.add(value);
  }
  return result;
}
