import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../data/datasources/plan_cas_session.dart';

class AppFailure {
  const AppFailure(this.title, this.message);
  final String title;
  final String message;

  static AppFailure from(Object error) {
    final text = error.toString().toLowerCase();
    bool hasStatus(int code) =>
        RegExp(r'\b(?:http|status(?: code)?)\s*[:=]?\s*' '$code' r'\b')
            .hasMatch(text);
    if (text.contains('przerwa techniczna')) {
      return const AppFailure('Przerwa techniczna UEK',
          'Serwis uczelni jest chwilowo niedostępny. Zapisane dane pozostają na urządzeniu.');
    }
    if (error is TimeoutException ||
        text.contains('timeout') ||
        text.contains('czas oczekiwania')) {
      return const AppFailure('Serwer nie odpowiada',
          'Połączenie trwało zbyt długo. Spróbuj ponownie za chwilę.');
    }
    if (error is HandshakeException ||
        text.contains('ssl') ||
        text.contains('certyfikat')) {
      return const AppFailure('Nie można bezpiecznie połączyć się z UEK',
          'Sprawdź datę urządzenia lub spróbuj innej sieci. Nie wyłączaj sprawdzania certyfikatów.');
    }
    if ([500, 502, 503, 504].any(hasStatus)) {
      return const AppFailure('Problem po stronie UEK',
          'Serwer uczelni jest chwilowo niedostępny. Spróbuj ponownie później.');
    }
    if (error is SocketException ||
        error is http.ClientException ||
        text.contains('socketexception')) {
      return const AppFailure(
          'Brak połączenia', 'Sprawdź dostęp do internetu i ponów próbę.');
    }
    if (error is PlanLoginException ||
        text.contains('logowania') ||
        hasStatus(401) ||
        hasStatus(403)) {
      return const AppFailure('Nie udało się zalogować',
          'Sesja mogła wygasnąć lub logowanie wymaga dodatkowego potwierdzenia. Ponów próbę lub zaloguj się ponownie.');
    }
    if (text.contains('database') || text.contains('sqlite')) {
      return const AppFailure('Nie udało się odczytać zapisanych danych',
          'Spróbuj ponownie. Jeśli problem się powtarza, uruchom ponownie aplikację.');
    }
    return const AppFailure('Nie udało się pobrać danych',
        'Ponów próbę. Jeśli problem się powtarza, serwis UEK mógł zmienić sposób udostępniania danych.');
  }
}
