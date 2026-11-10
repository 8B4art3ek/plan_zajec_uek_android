import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plan_zajec_uek/data/datasources/auth_service.dart';
import 'package:plan_zajec_uek/data/datasources/plan_directory.dart';
import 'package:plan_zajec_uek/data/datasources/schedule_remote_datasource.dart';
import 'package:plan_zajec_uek/presentation/providers/search_providers.dart';

class _Auth extends AuthService {
  @override
  Future<Credentials?> getCredentials() async =>
      const Credentials(username: 'test', password: 'test');
}

void main() {
  test('target schedule uses requested period without reading group settings',
      () async {
    final periods = <String?>[];
    final remote = ScheduleRemoteDatasource(client: MockClient((request) async {
      periods.add(request.url.queryParameters['okres']);
      return http.Response('<table></table>', 200);
    }));
    addTearDown(remote.close);
    final container = ProviderContainer(overrides: [
      planDirectoryProvider.overrideWithValue(PlanDirectory(remote, _Auth())),
    ]);
    addTearDown(container.dispose);
    final target = PlanTarget(
        name: 'Sala',
        uri: PlanDirectory.base
            .replace(queryParameters: {'typ': 'S', 'id': '1', 'okres': '3'}),
        kind: PlanKind.room);
    await container.read(targetScheduleProvider((target, 1)).future);
    await container.read(targetScheduleProvider((target, 3)).future);
    expect(periods, ['1', '3']);
  });

  test('search ignores accents, case, token order and extra whitespace', () {
    expect(matchesSearch('prof. Paweł Wołoszyn', '  woloszyn PAWEL '), isTrue);
    expect(matchesSearch('Paw.F CJ 302', '302 paw.f'), isTrue);
    expect(matchesSearch('Matematyka', 'fizyka'), isFalse);
  });

  test(
      'directory separates kinds, deduplicates targets and rejects unsafe links',
      () {
    final page = PlanDirectory.parse('''
      <a href="index.php?typ=N">Wykładowcy</a>
      <a href="index.php?typ=N&amp;id=42">Wołoszyn Paweł, prof.</a>
      <a href="index.php?typ=N&amp;id=42&amp;okres=1">Wołoszyn Paweł, prof.</a>
      <a href="index.php?typ=S&amp;id=12">Biblioteka 425</a>
      <a href="https://example.com/index.php?typ=N&amp;id=1">Obcy host</a>
      <a href="http://planzajec.uek.krakow.pl/index.php?typ=N&amp;id=1">HTTP</a>
      <a href="https://user@planzajec.uek.krakow.pl/index.php?typ=N&amp;id=1">Userinfo</a>
    ''', PlanDirectory.base, PlanKind.lecturer);
    expect(page.targets.single.name, 'Wołoszyn Paweł, prof.');
    expect(page.categories.values, ['Wykładowcy']);
  });

  test('catalogue follows categories once and preserves failed categories',
      () async {
    final requests = <Uri>[];
    final remote = ScheduleRemoteDatasource(client: MockClient((request) async {
      requests.add(request.url);
      final section = request.url.queryParameters['section'];
      final source = section == null
          ? '''
        <a href="?typ=N&amp;section=a">A</a><a href="?typ=N&amp;section=b">B</a>
      '''
          : section == 'a'
              ? '''
        <a href="?typ=N&amp;section=a">A</a><a href="?typ=N&amp;id=42">Osoba</a>
      '''
              : '';
      return http.Response.bytes(
          utf8.encode(source), section == 'b' ? 500 : 200,
          headers: {'content-type': 'text/html; charset=utf-8'});
    }));
    addTearDown(remote.close);
    final page =
        await PlanDirectory(remote, _Auth()).catalogue(PlanKind.lecturer);
    expect(page.targets.single.name, 'Osoba');
    expect(page.categories.values, ['B']);
    expect(requests.length, 3);
  });

  for (final kind in PlanKind.values) {
    test(
        'parses ${kind.name} schedule with correct columns and selected period',
        () async {
      final remote =
          ScheduleRemoteDatasource(client: MockClient((request) async {
        expect(request.url.queryParameters['okres'], '2');
        expect(request.headers['Authorization'], isNull);
        return http.Response.bytes(utf8.encode('''
          <table class="zajecia"><tr><th>Termin</th><th>Dzień</th><th>Przedmiot</th><th>Typ</th><th>${kind == PlanKind.lecturer ? 'Sala' : 'Nauczyciel'}</th><th>Grupa</th></tr>
          <tr><td>2026-10-20</td><td>Wt 09:45 - 11:15 (2g.)</td><td>Matematyka</td><td>wykład</td><td>${kind == PlanKind.lecturer ? 'Biblioteka 425' : 'dr Jan Kowalski'}</td><td>ZIISS1-1111</td></tr></table>
        '''), 200, headers: {'content-type': 'text/html; charset=utf-8'});
      }));
      addTearDown(remote.close);
      final target = PlanTarget(
          name:
              kind == PlanKind.lecturer ? 'dr Jan Kowalski' : 'Biblioteka 425',
          uri: PlanDirectory.base.replace(queryParameters: {
            'typ': kind == PlanKind.lecturer ? 'N' : 'S',
            'id': '1',
            'okres': '3'
          }),
          kind: kind);
      final entries = await PlanDirectory(remote, _Auth()).schedule(target, 2);
      expect(entries.single.subject, 'Matematyka');
      expect(entries.single.studentGroups, 'ZIISS1-1111');
      expect(entries.single.room, 'Biblioteka 425');
      expect(entries.single.lecturer, 'dr Jan Kowalski');
      expect(entries.single.startTime, '09:45');
    });
  }
}
