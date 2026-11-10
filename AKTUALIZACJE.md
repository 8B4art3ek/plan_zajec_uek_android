# Aktualizacje przez GitHub Releases

Publiczne repozytorium instalatorów: https://github.com/8B4art3ek/uek-plan-releases
Nie publikujemy w nim kodu źródłowego, kluczy podpisujących ani danych użytkowników.

## Pierwsza instalacja

Wersja 1.0.1 (build 2) wprowadza aktualizacje w ustawieniach aplikacji.
Trzeba zainstalować ją ręcznie na dotychczasową wersję, bez odinstalowywania.
Późniejsze wydania można pobierać w aplikacji. Android wymaga zatwierdzenia
instalacji i może poprosić o zezwolenie na instalowanie z tego źródła.
Pobieranie nadal wymaga internetu i pobiera cały APK; nie jest aktualizacją OTA kodu.

## Publikacja kolejnych wydań

1. Zwiększ `version` w `pubspec.yaml`, np. `1.0.2+3`. Liczba po `+` musi
   rosnąć przy każdym wydaniu. Nie zmieniaj identyfikatora aplikacji.
2. Uruchom `flutter analyze`, `flutter test`, następnie `./tool/build_release.ps1`.
3. Od 5 listopada 2026 publikujemy wyłącznie mniejszy `uek-plan-arm64-v8a.apk`.
   Skrypt tworzy go w `build/releases`. Nie dołączaj starego `uek-plan.apk`,
   nawet jeśli pozostał w katalogu po wcześniejszej kompilacji.
4. W repozytorium instalatorów utwórz Release z tagiem identycznym z wersją,
   poprzedzonym `v`, np. `v1.0.2+3`. Dołącz opis zmian i tylko instalator ARM64.
5. Opublikuj jako stabilne, najnowsze wydanie (nie prerelease).
6. Sprawdź publiczny endpoint
   `https://api.github.com/repos/8B4art3ek/uek-plan-releases/releases/latest`.
   Asset musi zawierać rozmiar i `digest` w formacie `sha256:...`.

## Wersje testowe

Prerelease ma oznaczenie np. `1.0.10-beta.1+11`. Liczba po `+` musi rosnąć
również dla wersji testowych. Na GitHubie ustaw `prerelease: true` i nie oznaczaj
wydania jako Latest. Publikujemy wyłącznie APK ARM64, z dotychczasowym podpisem.
Obecny aktualizator pomija prerelease, więc wersję testową pobiera się ręcznie
ze strony wydania. Nie trzeba odinstalowywać dotychczasowej aplikacji.
Przed publikacją instalatora wyślij odpowiadające mu źródła z licencją do
publicznego repozytorium `8B4art3ek/plan_zajec_uek_android`.

## Podpis aplikacji

Obecne wydania używają dotychczasowego lokalnego klucza debug do zachowania
zgodności z już zainstalowaną aplikacją. Nie jest to docelowa konfiguracja dla
szerszej dystrybucji. Przed nią trzeba zaplanować przejście na własny klucz release.
Zmiana klucza uniemożliwi zwykłą aktualizację istniejącej instalacji.
Nie usuwaj ani nie regeneruj obecnego klucza; przechowuj jego bezpieczną kopię
poza publicznym repozytorium. Kluczy i haseł nigdy nie dołączaj do wydania.

## Mniejsze instalatory od wersji 1.0.2

Biblioteki natywne są kompresowane w APK (`useLegacyPackaging = true`).
Android rozpakowuje je przy instalacji: rozmiar pobierania nie jest rozmiarem
zajmowanym na telefonie. Zachowujemy `keepDebugSymbols` silnika Fluttera z powodu
wcześniejszego błędu uruchamiania po stripowaniu w lokalnym Windows NDK.

Aktualizator od wersji 1.0.2 odczytuje ABI telefonu i wybiera dedykowany APK,
jeżeli jest dostępny. W przeciwnym razie pobiera uniwersalny `uek-plan.apk`.
Nowe wydania zawierają tylko ARM64. Bardzo stare instalacje bez obsługi wyboru ABI
muszą przejść na nowszą wersję ręcznie. Telefon musi obsługiwać ARM64;
nie podmieniamy nazwy na uniwersalną, bo taki plik nie działa na innych ABI.
Budujemy ARM64 przez `--target-platform android-arm64`, bez `--split-per-abi`,
aby nie dodawać przesunięcia do Android versionCode.

## Zabezpieczenia i ograniczenia

- Sprawdzanie przy wejściu do głównego ekranu i ręcznie w ustawieniach.
- Brak tokenów GitHuba w aplikacji; publiczne API może czasowo ograniczać zapytania.
- Pobieranie wyłącznie przez HTTPS z GitHuba i jego serwerów plików.
- Weryfikacja rozmiaru, SHA-256, identyfikatora, wersji i podpisu APK.
- Niekompletne lub anulowane pobranie nie może zostać zainstalowane.
- Pliki są w prywatnej pamięci podręcznej. Instalator dostaje dostęp tylko do katalogu aktualizacji.
- Nie ma cichej instalacji ani automatycznego pobierania dużych plików.
- Po zamknięciu procesu aplikacji pobieranie należy rozpocząć ponownie.
- Obsługa dotyczy Androida. Ewentualny wariant ze sklepu Play wymaga osobnej konfiguracji.
