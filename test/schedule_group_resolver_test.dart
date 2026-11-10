import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plan_zajec_uek/data/datasources/schedule_group_resolver.dart';
import 'package:plan_zajec_uek/data/datasources/plan_cas_session.dart';
import 'package:plan_zajec_uek/data/datasources/schedule_remote_datasource.dart';
import 'package:plan_zajec_uek/domain/entities/usos_import.dart';

const _data = UsosImportData(deanCodes: ['ZIISS1-2311AD'], languageGroups: []);

void main() {
  Future<UsosImportResult> resolve(String html, {int status = 200}) async {
    final remote = ScheduleRemoteDatasource(
        client: MockClient((_) async => http.Response(html, status)));
    try {
      return await ScheduleGroupResolver(remote: remote)
          .resolve(data: _data, username: 'test', password: 'test');
    } finally {
      remote.close();
    }
  }

  test('HTTP 500 propagates instead of becoming an empty list of matches',
      () async {
    await expectLater(resolve('Server error', status: 500), throwsException);
  });

  for (final html in [
    '<html><body></body></html>',
    '<title>Wymagane zalogowanie</title>',
    '<form><input type="password"></form>',
    '<title>Internal Server Error</title>',
  ]) {
    test('HTTP 200 with invalid catalog is reported as unreadable: $html',
        () async {
      await expectLater(
          resolve(html),
          throwsA(
              anyOf(isA<PlanCatalogException>(), isA<PlanLoginException>())));
    });
  }

  test('readable group catalog with no matching code returns unresolved group',
      () async {
    final result =
        await resolve('<a href="index.php?typ=G&id=123">ANOTHER-GROUP</a>');
    expect(result.imported, isEmpty);
    expect(result.unresolved.single.sourceLabel, 'ZIISS1-2311AD');
  });

  test('readable catalog resolves dynamically scraped dean code', () async {
    final result =
        await resolve('<a href="index.php?typ=G&id=123">ZIISS1-2311AD</a>');
    expect(result.imported.single.scheduleId, '123');
    expect(result.unresolved, isEmpty);
  });

  test('resolves from real-style categories without opening group schedules',
      () async {
    final requests = <Uri>[];
    final remote = ScheduleRemoteDatasource(client: MockClient((request) async {
      requests.add(request.url);
      expect(request.url.queryParameters['id'], isNull,
          reason:
              'Matching group codes must not download individual schedules');
      final category = request.url.queryParameters['grupa'];
      final source = switch (category) {
        'Informatyka Stosowana (IS)' =>
          '<a href="index.php?typ=G&amp;id=258981&amp;okres=1">ZIISS1-2311AD</a>',
        '*Centrum Językowe*' =>
          '<a href="index.php?typ=G&amp;id=900&amp;okres=1">CJ-S1-2/3-ANG.B1-06</a>',
        _ =>
          '<a href="index.php?typ=G&amp;grupa=Informatyka%20Stosowana%20(IS)">Informatyka Stosowana (IS)</a>'
              '<a href="index.php?typ=G&amp;grupa=*Centrum%20J%C4%99zykowe*">*Centrum Językowe*</a>',
      };
      return http.Response(source, 200,
          headers: {'content-type': 'text/html; charset=utf-8'});
    }));
    addTearDown(remote.close);
    final result = await ScheduleGroupResolver(remote: remote).resolve(
        username: 'test',
        password: 'test',
        data: const UsosImportData(deanCodes: [
          'ZIISS1-2311AD'
        ], languageGroups: [
          UsosLanguageGroup(
              languageName: 'angielski',
              languageCodeCandidates: ['ANG'],
              level: 'B1',
              groupNumber: 6,
              usosCourseCode: 'CJ-S1-2/3-ANG.B1',
              sourceText: '')
        ]));
    expect(result.imported.map((g) => g.scheduleId), ['258981', '900']);
    expect(result.unresolved, isEmpty);
    expect(requests, hasLength(3));
  });
}
