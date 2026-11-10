import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plan_zajec_uek/data/datasources/lecturer_directory.dart';

void main() {
  test('removes academic titles without damaging Polish names', () {
    expect(lecturerSearchName('prof. UEK dr hab. Paweł Wołoszyn'),
        'Paweł Wołoszyn');
    expect(lecturerSearchName('Żółć Anna-Maria, dr inż.'), 'Żółć Anna-Maria');
  });

  test('matches business cards, not teaching courses or similar names', () {
    final cards = LecturerDirectory.parseSearch('''
      <a href="/course/view.php?id=1">e-Wizytówka: Anna Nowak</a>
      <a href="/course/view.php?id=1&amp;lang=en">e-Wizytówka: Anna Nowak</a>
      <a href="/course/view.php?id=2">e-Wizytówka: Hanna Nowak</a>
      <a href="/course/view.php?id=3">Programowanie - Anna Nowak</a>
      <a href="https://example.com/course/view.php?id=4">e-Wizytówka: Anna Nowak</a>
      <a href="javascript:alert(1)">e-Wizytówka: Anna Nowak</a>
      <a href="/course/view.php?id=%">e-Wizytówka: Anna Nowak</a>
    ''', 'Nowak Anna, dr');
    expect(cards.single.uri.queryParameters['id'], '1');
  });

  test('extracts published email only from course content', () {
    final contact = LecturerDirectory.parseContact('''
      <div class="course-content">
        <p>Kontakt: prowadzacy@uek.krakow.pl.</p>
        <a href="mailto:prowadzacy@uek.krakow.pl">E-mail</a>
        <a href="https://teams.microsoft.com/l/team/123">Konsultacje</a>
        <a href="https://teams.cloud.microsoft/l/team/456">Wykład</a>
        <a href="https://teams.microsoft.com.example.org/">Podszywanie</a>
      </div>
      <footer>cel@uek.krakow.pl</footer>
    ''');
    expect(contact.emails, ['prowadzacy@uek.krakow.pl']);
    expect(
        LecturerDirectory.parseContact('<footer>cel@uek.krakow.pl</footer>')
            .emails,
        isEmpty);
  });

  test('public requests do not send app credentials and HTTP errors propagate',
      () async {
    final service = LecturerDirectory(client: MockClient((request) async {
      expect(request.headers.containsKey('authorization'), isFalse);
      expect(request.url.queryParameters['search'], 'Paweł Wołoszyn');
      return http.Response('', 503);
    }));
    addTearDown(service.close);
    await expectLater(
        service.search('prof. UEK dr hab. Paweł Wołoszyn'), throwsStateError);
  });

  test('live public e-business card lookup', () async {
    final service = LecturerDirectory();
    addTearDown(service.close);
    final cards = await service.search('prof. UEK dr hab. Paweł Wołoszyn');
    expect(cards, isNotEmpty);
    final contact = await service.contact(cards.first);
    expect(contact.emails, isNotEmpty);
  }, skip: !const bool.fromEnvironment('LIVE_UEK'));
}
