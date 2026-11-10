import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plan_zajec_uek/data/datasources/plan_cas_session.dart';
import 'package:plan_zajec_uek/data/datasources/schedule_remote_datasource.dart';

const _plan = 'https://planzajec.uek.krakow.pl/index.php';
const _cas = 'https://logowanie.uek.krakow.pl/cas/login';
const _password = 'hasło&+=';
const _form = '''<form method="post" action="login">
<input name="username"><div><input name="password" type="password"></div>
<input type="hidden" name="execution" value="token%+&amp;">
<input type="hidden" name="_eventId" value="submit">
<input type="hidden" name="geolocation">
</form>''';
const _schedule = '<meta charset="utf-8"><table class="zajecia">'
    '<tr><td>2026-10-23</td><td>Pt 09:00 - 10:30 (2g.)</td>'
    '<td>Język polski</td><td>wykład</td><td>Prowadzący</td><td>A</td>'
    '</tr></table>';

class _CasServer {
  final requests = <http.Request>[];
  final users = <String>[];
  Uri? target;
  bool rejectPassword = false;
  bool expirePlanSession = false;
  bool allowSso = false;

  http.Response redirect(String location, {String? cookie}) =>
      http.Response('', 302, headers: {
        'location': location,
        if (cookie != null) 'set-cookie': cookie,
      });

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    expect(request.followRedirects, isFalse);
    expect(request.headers['Authorization'], isNull);
    expect(request.url.toString(), isNot(contains(_password)));
    final cookie = request.headers['Cookie'] ?? '';
    if (request.url.host == 'planzajec.uek.krakow.pl') {
      expect(request.method, 'GET');
      expect(request.body, isEmpty);
      expect(cookie, isNot(contains('JSESSIONID')));
      expect(cookie, isNot(contains('TGC=')));
      if (request.url.queryParameters['ticket'] == 'ST-test') {
        expirePlanSession = false;
        return redirect(target.toString(),
            cookie: 'PHPSESSID=active; Path=/; Secure; HttpOnly');
      }
      if (cookie.contains('PHPSESSID=active') && !expirePlanSession) {
        return http.Response(_schedule, 200,
            headers: {'content-type': 'text/html; charset=utf-8'});
      }
      target = request.url;
      return redirect(Uri.parse(_cas)
          .replace(queryParameters: {'service': target.toString()}).toString());
    }
    expect(request.url.host, 'logowanie.uek.krakow.pl');
    expect(request.url.path, '/cas/login');
    expect(cookie, isNot(contains('PHPSESSID')));
    if (request.method == 'POST') {
      expect(cookie, contains('JSESSIONID=cas-session'));
      expect(cookie, contains('SECOND=2'));
      expect(request.bodyFields['password'], _password);
      expect(request.bodyFields['execution'], 'token%+&');
      expect(request.bodyFields['_eventId'], 'submit');
      expect(request.bodyFields['geolocation'], '');
      users.add(request.bodyFields['username']!);
      if (rejectPassword) return http.Response(_form, 200);
      return redirect(
          target!.replace(queryParameters: {
            ...target!.queryParameters,
            'ticket': 'ST-test',
          }).toString(),
          cookie: 'TGC=cas-ticket; Path=/cas; Secure');
    }
    if (allowSso && cookie.contains('TGC=cas-ticket')) {
      return redirect(target!.replace(queryParameters: {
        ...target!.queryParameters,
        'ticket': 'ST-test',
      }).toString());
    }
    return http.Response(_form, 200, headers: {
      'set-cookie': 'JSESSIONID=cas-session; Path=/cas; Secure; HttpOnly, '
          'SECOND=2; Expires=Wed, 01 Jan 2031 00:00:00 GMT; Path=/cas; Secure',
    });
  }
}

void main() {
  late _CasServer server;
  late ScheduleRemoteDatasource remote;
  setUp(() {
    server = _CasServer();
    remote = ScheduleRemoteDatasource(client: MockClient(server.handle));
  });
  tearDown(() => remote.close());

  test('CAS form, tokens, cookies and service ticket return requested plan',
      () async {
    final result = await remote.fetchScheduleHtml(
        groupId: '123', username: 'student', password: _password, okres: 4);
    expect(result, _schedule);
    expect(server.users, ['student']);
    expect(server.target!.queryParameters,
        {'typ': 'G', 'id': '123', 'okres': '4'});
    expect(server.requests.last.url, server.target);
  });

  test('concurrent group, room and lecturer lookups share one CAS login',
      () async {
    await Future.wait([
      for (final type in ['G', 'S', 'N'])
        remote.fetchAuthenticatedPlanHtml(
            uri: Uri.parse('$_plan?typ=$type&id=123&okres=4'),
            username: 'student',
            password: _password),
    ]);
    expect(server.users, ['student']);
    expect(server.requests.last.url.queryParameters['typ'], 'N');
  });

  test('expired plan session renews automatically using CAS SSO', () async {
    await remote.verifyCredentials(username: 'student', password: _password);
    server.expirePlanSession = true;
    server.allowSso = true;
    expect(
        await remote.fetchPlanIndexHtml(
            username: 'student', password: _password),
        _schedule);
    expect(server.users, ['student']);
  });

  test('changing account clears both plan and CAS session cookies', () async {
    await remote.verifyCredentials(username: 'first', password: _password);
    server.allowSso = true;
    await remote.verifyCredentials(username: 'second', password: _password);
    expect(server.users, ['first', 'second']);
  });

  test('rejected credentials are not retried in a loop or treated as plan',
      () async {
    server.rejectPassword = true;
    await expectLater(
        remote.verifyCredentials(username: 'student', password: _password),
        throwsA(isA<PlanLoginException>()));
    expect(server.users, ['student']);
  });

  test('diagnostics show stages without passwords, tokens, cookies or URLs',
      () async {
    server.rejectPassword = true;
    try {
      await remote.verifyCredentials(username: 'student', password: _password);
      fail('Expected CAS failure');
    } on PlanLoginException catch (error) {
      expect(error.steps, [
        'Plan UEK: GET → HTTP 302',
        'CAS: GET → HTTP 200',
        'CAS: POST → HTTP 200',
      ]);
      final text = error.steps.join('\n');
      for (final secret in [
        _password,
        'student',
        'token%+&',
        'cas-session',
        'https://',
        'ST-test'
      ]) {
        expect(text, isNot(contains(secret)));
      }
    }
  });

  test('redirect loop is bounded', () async {
    var requests = 0;
    final looping =
        ScheduleRemoteDatasource(client: MockClient((request) async {
      requests++;
      return http.Response('', 302, headers: {'location': _plan});
    }));
    addTearDown(looping.close);
    await expectLater(looping.verifyCredentials(username: 'a', password: 'b'),
        throwsA(isA<PlanLoginException>()));
    expect(requests, 12);
  });

  for (final destination in [
    'https://example.com/login',
    'http://logowanie.uek.krakow.pl/cas/login',
    'https://logowanie.uek.krakow.pl:444/cas/login',
    'https://logowanie.uek.krakow.pl/other',
    'https://logowanie.uek.krakow.pl/cas/login?service=https://example.com/',
  ]) {
    test('blocks unsafe redirect before contacting $destination', () async {
      var requests = 0;
      final unsafe = ScheduleRemoteDatasource(client: MockClient((_) async {
        requests++;
        return http.Response('', 302, headers: {'location': destination});
      }));
      addTearDown(unsafe.close);
      await expectLater(unsafe.verifyCredentials(username: 'a', password: 'b'),
          throwsA(anyOf(isA<PlanLoginException>(), isA<ArgumentError>())));
      expect(requests, 1);
    });
  }

  for (final action in [
    'https://example.com/login',
    _plan,
    'http://logowanie.uek.krakow.pl/cas/login'
  ]) {
    test('never submits credentials to unsafe form action $action', () async {
      var posts = 0;
      final unsafe =
          ScheduleRemoteDatasource(client: MockClient((request) async {
        if (request.method == 'POST') posts++;
        if (request.url.host == 'planzajec.uek.krakow.pl') {
          return http.Response('', 302, headers: {'location': _cas});
        }
        return http.Response(
            _form.replaceFirst('action="login"', 'action="$action"'), 200);
      }));
      addTearDown(unsafe.close);
      await expectLater(unsafe.verifyCredentials(username: 'a', password: 'b'),
          throwsA(isA<PlanLoginException>()));
      expect(posts, 0);
    });
  }

  test('307 after password POST does not forward password to plan service',
      () async {
    final unsafe = ScheduleRemoteDatasource(client: MockClient((request) async {
      if (request.method == 'POST') {
        return http.Response('', 307, headers: {'location': _plan});
      }
      if (request.url.host == 'planzajec.uek.krakow.pl') {
        return http.Response('', 302, headers: {'location': _cas});
      }
      return http.Response(_form, 200);
    }));
    addTearDown(unsafe.close);
    await expectLater(unsafe.verifyCredentials(username: 'a', password: 'b'),
        throwsA(isA<PlanLoginException>()));
  });

  test('login/error HTML returned with HTTP 200 is never treated as plan',
      () async {
    final invalid = ScheduleRemoteDatasource(
        client: MockClient((_) async =>
            http.Response('<title>Internal Server Error</title>', 200)));
    addTearDown(invalid.close);
    await expectLater(invalid.fetchPlanIndexHtml(username: 'a', password: 'b'),
        throwsA(isA<PlanLoginException>()));
  });
}
