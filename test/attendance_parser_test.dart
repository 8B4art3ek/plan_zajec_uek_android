import 'package:flutter_test/flutter_test.dart';
import 'package:plan_zajec_uek/data/datasources/attendance_parser.dart';

void main() {
  test('groups by identifier semester, newest first, without mixing subjects',
      () {
    final snapshot = const AttendanceParser().parseWebViewResult({
      'headers': ['Identyfikator', 'Status', 'Data rejestracji'],
      'rows': [
        [
          'Matematyka, CW, grupa 1\n25/26Z - MAT',
          'Zarejestrowano',
          '2027-10-01'
        ],
        ['Matematyka, CW, grupa 2\n25/26L - MAT', 'Brak obecności', ''],
        ['Matematyka, LAB, grupa 3\n26/27Z - MAT', 'Zarejestrowano', ''],
        ['Matematyka, WYK, grupa 1\n2026 / 2027 z - MAT', 'Zarejestrowano', ''],
        ['Fizyka, CW, grupa 1', 'Zarejestrowano', '2026-10-01'],
        ['Chemia, CW, grupa 1\n26/29Z - CH', 'Zarejestrowano', ''],
      ],
    });
    final semesters = snapshot.semesters;
    expect(semesters.map((s) => s.code),
        ['2026/2027Z', '2025/2026L', '2025/2026Z', null]);
    expect(semesters.first.label, 'Semestr zimowy 2026/2027');
    expect(semesters[1].label, 'Semestr letni 2025/2026');
    expect(semesters.last.label, 'Bez oznaczenia semestru');
    expect(semesters.first.subjects.single.records.map((r) => r.classType),
        ['LAB', 'WYK']);
    expect(
        semesters[2].subjects.single.records.single.registeredAt, '2027-10-01');
    expect(semesters.last.subjects, hasLength(2));
  });

  test('parses attendance table returned by the WebView', () {
    const raw =
        '{"title":"Moje obecnosci","isLogin":false,"headers":["Termin otwarcia","Data rejestracji","Identyfikator","Status"],"rows":[["2026-10-15","2026-10-15","Matematyka, WYK, grupa\\n1\\n26/27Z - MAT","Zarejestrowano"],["2026-10-14","2026-10-14","Matematyka, CW, grupa\\n2\\n26/27Z - MAT","Brak obecnosci"]]}';

    final snapshot = const AttendanceParser().parseWebViewResult(raw);

    expect(snapshot.pageTitle, 'Moje obecnosci');
    expect(snapshot.requiresLogin, isFalse);
    expect(snapshot.headers, [
      'Termin otwarcia',
      'Data rejestracji',
      'Identyfikator',
      'Status',
    ]);
    expect(snapshot.subjects, hasLength(1));
    expect(snapshot.subjects.single.name, 'Matematyka');
    expect(snapshot.subjects.single.records, hasLength(2));
    expect(snapshot.subjects.single.registeredCount, 1);
    expect(
        snapshot.subjects.single.records
            .singleWhere((r) => r.classType == 'WYK')
            .classDetails,
        'WYK, grupa 1 · 26/27Z - MAT');
    expect(
      snapshot.subjects.single.records
          .singleWhere((r) => r.classType == 'CW')
          .classType,
      'CW',
    );
  });

  test('preserves empty cells so dates and statuses keep their column', () {
    final snapshot = const AttendanceParser().parseWebViewResult({
      'title': 'Moje obecności',
      'headers': [
        'Termin otwarcia',
        'Data rejestracji',
        'Identyfikator',
        'Status'
      ],
      'rows': [
        ['2026-10-15', '', 'Matematyka, CW, grupa 1', 'Brak obecności'],
      ],
    });

    final record = snapshot.subjects.single.records.single;
    expect(record.subjectName, 'Matematyka');
    expect(record.registeredAt, isEmpty);
    expect(record.status, 'Brak obecności');
    expect(record.isRegistered, isFalse);
  });
}
