import 'dart:async';
import 'dart:convert';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:crypto/crypto.dart';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;

class PlanLoginException implements Exception {
  const PlanLoginException(this.message, {this.steps = const []});
  final String message;
  final List<String> steps;
  @override
  String toString() => message;
}

/// In-memory CAS session shared by all requests to the timetable service.
class PlanCasSession {
  PlanCasSession(this._client, {required this.timeout});

  static const planHost = 'planzajec.uek.krakow.pl';
  static const _casHost = 'logowanie.uek.krakow.pl';
  final http.Client _client;
  final Duration timeout;
  CookieJar _cookies = CookieJar();
  String? _identity;
  Future<void> _pending = Future.value();
  bool _closed = false;

  void close() {
    _closed = true;
    _cookies = CookieJar();
    _identity = null;
    _client.close();
  }

  Future<http.Response> get(Uri uri, String username, String password) async {
    _validatePlanUri(uri);
    // Serialize login/refresh so concurrent lookups cannot replace CAS cookies.
    final previous = _pending;
    final done = Completer<void>();
    _pending = done.future;
    await previous;
    try {
      if (_closed) throw StateError('Połączenie z planem jest zamknięte.');
      final identity = sha256
          .convert(utf8.encode(jsonEncode([username, password])))
          .toString();
      if (_identity != identity) {
        _cookies = CookieJar();
        _identity = identity;
      }
      final steps = <String>[];
      try {
        return await _getAuthenticated(uri, username, password, steps);
      } on PlanLoginException catch (error) {
        throw PlanLoginException(error.message,
            steps: List.unmodifiable(steps));
      }
    } finally {
      done.complete();
    }
  }

  Future<http.Response> _getAuthenticated(
      Uri target, String username, String password, List<String> steps) async {
    final watch = Stopwatch()..start();
    var uri = target;
    var method = 'GET';
    Map<String, String>? fields;
    var submitted = false;
    for (var hop = 0; hop < 12; hop++) {
      _validateNavigation(uri);
      if (_closed) throw StateError('Połączenie z planem jest zamknięte.');
      final remaining = timeout - watch.elapsed;
      if (remaining <= Duration.zero) throw _timeout();
      final request = http.Request(method, uri)
        ..followRedirects = false
        ..headers.addAll({
          'Accept': 'text/html,application/xhtml+xml',
          'Accept-Language': 'pl,en;q=0.9',
        });
      final cookies = await _cookies.loadForRequest(uri);
      if (cookies.isNotEmpty) {
        request.headers['Cookie'] = cookies
            .map((cookie) => '${cookie.name}=${cookie.value}')
            .join('; ');
      }
      if (fields != null) request.bodyFields = fields;
      final response = await (() async {
        final streamed = await _client.send(request);
        return http.Response.fromStream(streamed);
      })()
          .timeout(remaining, onTimeout: () => throw _timeout());
      steps.add('${uri.host == planHost ? 'Plan UEK' : 'CAS'}: '
          '$method → HTTP ${response.statusCode}');
      await _saveCookies(uri, response);

      if (const {301, 302, 303, 307, 308}.contains(response.statusCode)) {
        final location = response.headers['location'];
        if (location == null) {
          throw const PlanLoginException(
              'Serwer UEK zwrócił niepełne przekierowanie logowania.');
        }
        final next = uri.resolve(location);
        _validateNavigation(next);
        // Never replay a password-bearing POST through a 307/308 redirect.
        if (fields != null && const {307, 308}.contains(response.statusCode)) {
          throw const PlanLoginException(
              'Serwer CAS zwrócił nieobsługiwane przekierowanie formularza.');
        }
        uri = next;
        method = 'GET';
        fields = null;
        continue;
      }
      if (response.statusCode != 200) {
        throw PlanLoginException(response.statusCode == 401
            ? 'Logowanie UEK nie powiodło się. Sprawdź login i hasło.'
            : 'Serwer UEK jest niedostępny (HTTP ${response.statusCode}). Spróbuj później.');
      }
      final document =
          html.parse(utf8.decode(response.bodyBytes, allowMalformed: true));
      final passwordInput = document.querySelector('input[type="password"]');
      if (uri.host == planHost) {
        final title =
            (document.querySelector('title')?.text ?? '').toLowerCase();
        if (passwordInput != null ||
            title.contains('internal server error') ||
            title.contains('wymagane zalogowanie')) {
          throw const PlanLoginException(
              'Serwer UEK nie zwrócił planu po zalogowaniu. Spróbuj ponownie później.');
        }
        return response;
      }
      var form = passwordInput?.parent;
      while (form != null && form.localName != 'form') {
        form = form.parent;
      }
      if (form == null || submitted) {
        throw const PlanLoginException(
            'CAS nie zakończył logowania. Sprawdź dane lub wymagane dodatkowe potwierdzenie logowania.');
      }
      final action = uri.resolve(form.attributes['action'] ?? '');
      _validateCasLogin(action);
      if ((form.attributes['method'] ?? 'get').toLowerCase() != 'post') {
        throw const PlanLoginException(
            'Nieobsługiwany formularz logowania CAS.');
      }
      final usernameInput = form.querySelector('input[name="username"]');
      final passwordName = passwordInput!.attributes['name'];
      if (usernameInput == null || passwordName == null) {
        throw const PlanLoginException('Nie znaleziono pól logowania CAS.');
      }
      if ((form.querySelector('input[name="execution"]')?.attributes['value'] ??
              '')
          .isEmpty) {
        throw const PlanLoginException('Brak tokenu formularza logowania CAS.');
      }
      fields = {
        for (final input in form.querySelectorAll('input[name]'))
          if (input.attributes['type']?.toLowerCase() == 'hidden' &&
              !input.attributes.containsKey('disabled'))
            input.attributes['name']!: input.attributes['value'] ?? '',
        'username': username,
        passwordName: password,
      };
      final submitter = form.querySelector(
          'button[type="submit"][name], input[type="submit"][name]');
      if (submitter != null) {
        fields.putIfAbsent(submitter.attributes['name']!,
            () => submitter.attributes['value'] ?? '');
      }
      // CAS stores the service in its execution token; retain all hidden fields.
      submitted = true;
      uri = action;
      method = 'POST';
    }
    throw const PlanLoginException(
        'Zbyt wiele przekierowań podczas logowania do planu UEK.');
  }

  Future<void> _saveCookies(Uri uri, http.Response response) async {
    final header = response.headers['set-cookie'];
    if (header == null) return;
    final cookies = <Cookie>[];
    // package:http joins repeated headers; do not split the comma in Expires.
    for (final value in header.split(RegExp(r',(?=\s*[^;,\s]+=)'))) {
      try {
        final cookie = Cookie.fromSetCookieValue(value.trim());
        final domain = cookie.domain?.replaceFirst(RegExp(r'^\.'), '');
        if (domain == null ||
            uri.host == domain ||
            uri.host.endsWith('.$domain')) {
          cookies.add(cookie);
        }
      } on FormatException {
        // An invalid optional cookie must not drop the valid session cookie.
      }
    }
    await _cookies.saveFromResponse(uri, cookies);
  }

  static void _validatePlanUri(Uri uri) {
    if (!_isHttps(uri) || uri.host != planHost) {
      throw ArgumentError('Niedozwolony adres serwera planu zajęć.');
    }
  }

  static bool _isHttps(Uri uri) =>
      uri.scheme == 'https' && uri.port == 443 && uri.userInfo.isEmpty;

  static void _validateNavigation(Uri uri) {
    if (!_isHttps(uri) || !const {planHost, _casHost}.contains(uri.host)) {
      throw const PlanLoginException(
          'Zablokowano przekierowanie poza serwisy UEK.');
    }
    if (uri.host == _casHost) _validateCasLogin(uri);
  }

  static void _validateCasLogin(Uri uri) {
    if (!_isHttps(uri) || uri.host != _casHost || uri.path != '/cas/login') {
      throw const PlanLoginException('Nieprawidłowy adres formularza CAS UEK.');
    }
    final service = uri.queryParameters['service'];
    if (service != null) _validatePlanUri(Uri.parse(service));
  }

  static TimeoutException _timeout() => TimeoutException(
      'Serwer planu zajęć lub CAS nie odpowiada. Spróbuj ponownie.');
}
