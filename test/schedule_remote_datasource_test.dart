import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plan_zajec_uek/data/datasources/schedule_remote_datasource.dart';

void main() {
  test('encodes URL parameters and decodes quoted UTF-8 charset', () async {
    final remote = ScheduleRemoteDatasource(client: MockClient((request) async {
      expect(request.url.queryParameters['id'], '123&okres=1');
      expect(request.url.queryParameters['okres'], '2');
      expect(request.headers['Authorization'], isNull);
      expect(request.url.toString(), isNot(contains('hasło')));
      return http.Response.bytes(utf8.encode('Język, ćwiczenia'), 200,
          headers: {'content-type': 'text/html; charset="utf-8"'});
    }));
    addTearDown(remote.close);
    expect(
        await remote.fetchScheduleHtml(
            groupId: '123&okres=1',
            username: 'login',
            password: 'hasło',
            okres: 2),
        'Język, ćwiczenia');
  });

  test('does not send credentials to an external or insecure URL', () async {
    var requests = 0;
    final remote = ScheduleRemoteDatasource(client: MockClient((_) async {
      requests++;
      return http.Response('', 200);
    }));
    addTearDown(remote.close);
    for (final url in [
      'https://example.com/',
      'http://planzajec.uek.krakow.pl/',
      'https://planzajec.uek.krakow.pl:444/'
    ]) {
      await expectLater(
          remote.fetchAuthenticatedPlanHtml(
              uri: Uri.parse(url), username: 'login', password: 'hasło'),
          throwsArgumentError);
    }
    expect(requests, 0);
  });

  test('times out instead of leaving refresh running indefinitely', () async {
    final response = Completer<http.Response>();
    final remote = ScheduleRemoteDatasource(
        client: MockClient((_) => response.future),
        requestTimeout: const Duration(milliseconds: 10));
    addTearDown(remote.close);
    await expectLater(
        remote.verifyCredentials(username: 'test', password: 'test'),
        throwsA(isA<TimeoutException>()));
    response.complete(http.Response('', 200));
  });

  test('decodes Polish ISO-8859-2 characters', () async {
    final remote = ScheduleRemoteDatasource(
        client: MockClient((_) async => http.Response.bytes(
            [0xA1, 0xB1, 0xA3, 0xB3, 0xF3, 0xBF], 200,
            headers: {'content-type': 'text/html; charset=iso-8859-2'})));
    addTearDown(remote.close);
    expect(await remote.fetchPlanIndexHtml(username: 'test', password: 'test'),
        'ĄąŁłóż');
  });
}
