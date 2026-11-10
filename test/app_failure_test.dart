import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:plan_zajec_uek/core/app_failure.dart';

void main() {
  test('classifies common errors without exposing technical or secret details',
      () {
    final cases = <Object, String>{
      TimeoutException('secret'): 'Serwer nie odpowiada',
      const SocketException('secret'): 'Brak połączenia',
      http.ClientException('SSL secret'):
          'Nie można bezpiecznie połączyć się z UEK',
      Exception('HTTP 503 secret'): 'Problem po stronie UEK',
      Exception('HTTP 401 secret'): 'Nie udało się zalogować',
      Exception('database_closed secret'):
          'Nie udało się odczytać zapisanych danych',
      Exception('Przerwa techniczna secret'): 'Przerwa techniczna UEK',
      Exception('secret ticket=500123'): 'Nie udało się pobrać danych',
    };
    for (final entry in cases.entries) {
      final failure = AppFailure.from(entry.key);
      expect(failure.title, entry.value);
      expect('${failure.title} ${failure.message}', isNot(contains('secret')));
    }
  });
}
