import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:plan_zajec_uek/data/datasources/usos_import_parser.dart';

void main() {
  test('extracts only the bracketed dean group codes from USOS', () {
    final rawResult = jsonEncode({
      'text': '''
Grupa dziekańska: ZIISS1-2311AD [ZIISS1-2311AD]
Grupa dziekańska: [ZIISS1-1213]
Grupa dziekańska: [ZIISS1-1113]
''',
      'rows': <String>[],
    });

    final result = const UsosImportParser().parseWebViewResult(rawResult);

    expect(
      result.deanCodes,
      ['ZIISS1-2311AD', 'ZIISS1-1213', 'ZIISS1-1113'],
    );
  });

  test('uses dean codes captured directly by the WebView', () {
    final rawResult = jsonEncode({
      'text': 'dowolna tresc strony',
      'rows': <String>[],
      'deanCodes': ['ZIISS1-2311AD', 'ZIISS1-1213', 'ZIISS1-1113'],
    });

    final result = const UsosImportParser().parseWebViewResult(rawResult);

    expect(
      result.deanCodes,
      ['ZIISS1-2311AD', 'ZIISS1-1213', 'ZIISS1-1113'],
    );
  });

  test('adds a zero-padded group number to a language course code', () {
    final rawResult = jsonEncode({
      'text': '''
Język angielski, poziom B1 (3 semestr) [CJ-S1-2/3-ANG.B1]
Semestr zimowy 2026/2027
Lektorat, grupa nr 6
każda środa, 9:45 - 11:15
''',
      'rows': <String>[],
    });

    final result = const UsosImportParser().parseWebViewResult(rawResult);

    expect(result.languageGroups, hasLength(1));
    expect(
      result.languageGroups.single.scheduleCodeCandidates(null),
      ['CJ-S1-2/3-ANG.B1-06'],
    );
  });

  test('does not mix group numbers between adjacent language courses', () {
    final rawResult = jsonEncode({
      'text': '''
Język angielski, poziom B1 (3 semestr) [CJ-S1-2/3-ANG.B1]
Semestr zimowy 2026/2027
Lektorat, grupa nr 6
Język hiszpański, poziom A1 (3 semestr) [CJ-S1-2/3-HIS.A1]
Semestr zimowy 2026/2027
Lektorat, grupa nr 19
''',
      'rows': <String>[],
    });

    final result = const UsosImportParser().parseWebViewResult(rawResult);
    final codes = result.languageGroups
        .map((group) => group.scheduleCodeCandidates(null).single)
        .toList();

    expect(codes, ['CJ-S1-2/3-ANG.B1-06', 'CJ-S1-2/3-HIS.A1-19']);
  });
}
