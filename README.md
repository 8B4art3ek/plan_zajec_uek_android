# Niezbędnik Studenta

Aplikacja Flutter na Androida umożliwiająca przeglądanie planu zajęć UEK poza stroną uczelni: import grup z USOS,
obecności z portalu uczelni i własne wydarzenia.

## Uruchomienie

Wymagane: Flutter, Android SDK i JDK 21. W `android/gradle.properties`
ustaw `org.gradle.java.home` na istniejący katalog JDK na swoim komputerze.

```sh
flutter pub get
flutter run
```

## Sprawdzanie

```sh
flutter analyze
flutter test
flutter build apk --debug
```

Testy obejmują parsowanie i ładowanie obecności, import grup, filtrowanie planu,
odświeżanie, obsługę połączeń, kafelki i edycję własnych wydarzeń.
Używają danych testowych, bez logowania na konto uczelni.

## Nazwa i ikona

Nazwa interfejsu: `lib/core/app_identity.dart`.
Nazwa w Androidzie: `android/app/src/main/res/values/strings.xml`.
Źródła ikony i prompt: `assets/branding/README.md`.
Rozmiary ikon można odtworzyć poleceniem `./tool/generate_icons.ps1`.

Techniczna nazwa pakietu Dart i identyfikator Androida pozostają niezmienione,
aby zachować zgodność z istniejącą instalacją i jej danymi.

## Dane i logowanie

Plan i ustawienia są przechowywane lokalnie w SQLite, a dane logowania
w bezpiecznej pamięci urządzenia. Pobieranie danych wymaga dostępu
do serwisów UEK. Formularze automatycznego logowania sprawdzają HTTPS
i dozwoloną domenę przed wpisaniem danych.

Konfiguracja release nadal używa klucza debug. Przed publikacją w sklepie
trzeba skonfigurować własny klucz podpisujący.

## Licencja

Kod projektu jest udostępniany na licencji GNU General Public License,
wersja 3 (GPL-3.0-only). Pełny tekst znajduje się w pliku [LICENSE](LICENSE).
Copyright (C) 2026 8B4art3ek i pozostali autorzy projektu.

Możesz używać, modyfikować i rozpowszechniać kod zgodnie z tą licencją.
Przy rozpowszechnianiu wersji binarnych należy zapewnić odbiorcom dostęp
do odpowiadających im źródeł zgodnie z GPL-3.0. Program jest udostępniany
bez gwarancji, w zakresie dopuszczonym przez prawo.

Biblioteki i inne zależności zachowują własne licencje. Aplikacja nie jest
oficjalnym produktem Uniwersytetu Ekonomicznego w Krakowie. Licencja kodu
nie nadaje praw do danych ani znaków uczelni i przewoźników, a dostęp do
zewnętrznych serwisów podlega ich odrębnym warunkom.

Do repozytorium nie należy dodawać danych logowania, sesji, lokalnych baz
danych, plików środowiskowych ani kluczy podpisujących APK.
