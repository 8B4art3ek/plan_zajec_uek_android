import 'package:flutter_test/flutter_test.dart';
import 'package:plan_zajec_uek/domain/entities/attendance_link.dart';

void main() {
  test('accepts UEK attendance QR and a manually entered spaced code', () {
    expect(
        parseAttendanceLink('https://portal.uek.krakow.pl/obecnosc/123456789')
            ?.path,
        '/obecnosc/123456789');
    expect(parseAttendanceLink('123 456 789')?.toString(),
        'https://portal.uek.krakow.pl/obecnosc/123456789');
  });
  for (final value in [
    'https://evil.example/obecnosc/123456789',
    'http://portal.uek.krakow.pl/obecnosc/123456789',
    'https://portal.uek.krakow.pl.evil.example/obecnosc/123456789',
    'https://portal.uek.krakow.pl:444/obecnosc/123456789',
    'https://user@portal.uek.krakow.pl/obecnosc/123456789',
    'https://portal.uek.krakow.pl/obecnosc/123456789?next=https://evil.example',
    'https://portal.uek.krakow.pl/dashboard',
    'javascript:alert(1)',
    '123'
  ]) {
    test('rejects unsafe or unrelated QR $value', () {
      expect(parseAttendanceLink(value), isNull);
    });
  }
  test('allows CAS only for the portal service, never an external service', () {
    expect(
        isAttendanceNavigation(Uri.https(
            'logowanie.uek.krakow.pl',
            '/cas/login',
            {'service': 'https://portal.uek.krakow.pl/obecnosc/123456789'})),
        isTrue);
    expect(
        isAttendanceNavigation(Uri.https('logowanie.uek.krakow.pl',
            '/cas/login', {'service': 'https://evil.example/'})),
        isFalse);
    expect(isAttendanceNavigation(Uri.parse('https://evil.example/')), isFalse);
    expect(isAttendanceNavigation(Uri.parse('http://portal.uek.krakow.pl/')),
        isFalse);
  });
}
