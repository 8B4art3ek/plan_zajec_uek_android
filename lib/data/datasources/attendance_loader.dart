import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'attendance_parser.dart';
import 'auth_service.dart';

class AttendanceLoadState {
  const AttendanceLoadState({
    this.loading = true,
    this.status = 'Łączę z portalem UEK.',
    this.snapshot,
    this.error,
  });

  final bool loading;
  final String status;
  final AttendanceSnapshot? snapshot;
  final String? error;
}

class AttendanceLoader extends ChangeNotifier {
  AttendanceLoader({
    required this.readCredentials,
    required this.openPage,
    required this.readSnapshot,
    required this.submitLogin,
    this.openNextPage,
    this.firstPage,
    this.maxPages = 500,
    this.overallTimeout = const Duration(minutes: 3),
    this.timeout = const Duration(seconds: 45),
    this.pollInterval = const Duration(milliseconds: 400),
  });

  final Future<Credentials?> Function() readCredentials;
  final Future<void> Function(bool forceReload) openPage;
  final Future<AttendanceSnapshot> Function() readSnapshot;
  final Future<bool> Function(Credentials credentials) submitLogin;
  final Future<void> Function(Uri url)? openNextPage;
  final Uri? firstPage;
  final int maxPages;
  final Duration overallTimeout;
  final Duration timeout;
  final Duration pollInterval;

  AttendanceLoadState _state = const AttendanceLoadState();
  AttendanceLoadState get state => _state;

  Future<void>? _activeLoad;
  bool _disposed = false;

  Future<void> load({bool forceReload = false}) {
    if (_disposed) return Future<void>.value();
    return _activeLoad ??= _load(forceReload).whenComplete(() {
      _activeLoad = null;
    });
  }

  Future<void> _load(bool forceReload) async {
    _update(AttendanceLoadState(
      status: forceReload ? 'Odświeżam obecności.' : 'Pobieram obecności.',
    ));

    try {
      final credentials = await readCredentials().timeout(timeout);
      if (_disposed) return;
      if (credentials == null) {
        _update(const AttendanceLoadState(
          loading: false,
          status: 'Zaloguj się ponownie w aplikacji.',
          error: 'Brak zapisanych danych logowania.',
        ));
        return;
      }

      await openPage(forceReload).timeout(timeout);
      if (_disposed) return;
      final stopwatch = Stopwatch()..start();
      final overall = Stopwatch()..start();
      final submittedDocuments = <String>{};
      final visitedPages = <int>{};
      final pages = <AttendanceSnapshot>[];
      final rows = <String, List<String>>{};
      Uri? expectedPage = firstPage;
      AttendanceSnapshot? lastSnapshot;
      Duration remaining() {
        final page = timeout - stopwatch.elapsed;
        final total = overallTimeout - overall.elapsed;
        return page < total ? page : total;
      }

      // Odczyt DOM działa również wtedy, gdy tabela doładuje się po onPageFinished.
      while (!_disposed &&
          stopwatch.elapsed < timeout &&
          overall.elapsed < overallTimeout) {
        AttendanceSnapshot? snapshot;
        try {
          snapshot = await readSnapshot().timeout(remaining());
        } catch (_) {
          // Podczas przekierowania WebView może na chwilę utracić kontekst JS.
        }
        if (_disposed) return;

        if (snapshot != null && snapshot.isReady) {
          lastSnapshot = snapshot;
          if (snapshot.requiresLogin) {
            final document = snapshot.documentId.isEmpty
                ? snapshot.pageUrl
                : snapshot.documentId;
            if (!submittedDocuments.contains(document)) {
              if (submittedDocuments.length >= 3) {
                throw Exception('Portal UEK nie przyjął danych logowania.');
              }
              submittedDocuments.add(document);
              _update(const AttendanceLoadState(
                status: 'Loguję do portalu UEK.',
              ));
              try {
                final submitted =
                    await submitLogin(credentials).timeout(remaining());
                if (!submitted) submittedDocuments.remove(document);
              } catch (_) {
                // Wysłanie formularza mogło już uruchomić nową stronę.
              }
            }
          } else if (snapshot.hasAttendanceTable &&
              (snapshot.hasRows || snapshot.isEmpty) &&
              _isExpectedPage(snapshot, expectedPage)) {
            final current = parseAttendancePageUrl(snapshot.pageUrl);
            final number = int.parse(current?.queryParameters['page'] ?? '1');
            if (!visitedPages.add(number)) {
              throw Exception(
                  'Portal zwrócił ponownie tę samą stronę obecności.');
            }
            if (pages.isNotEmpty &&
                !listEquals(pages.first.headers, snapshot.headers)) {
              throw Exception(
                  'Portal zmienił układ tabeli podczas pobierania obecności.');
            }
            pages.add(snapshot);
            for (final row in snapshot.rows) {
              rows.putIfAbsent(jsonEncode(row), () => row);
            }
            final nextUrl = snapshot.nextPageUrl;
            if (nextUrl != null) {
              final next = parseAttendancePageUrl(nextUrl);
              if (next == null ||
                  int.parse(next.queryParameters['page'] ?? '1') !=
                      number + 1) {
                throw Exception(
                    'Nieprawidłowy odnośnik do kolejnej strony obecności.');
              }
              if (pages.length >= maxPages || openNextPage == null) {
                throw Exception(
                    'Nie udało się pobrać wszystkich stron obecności.');
              }
              expectedPage = next;
              stopwatch.reset();
              _update(AttendanceLoadState(
                  status: 'Pobieram obecności: strona ${number + 1}.'));
              final remaining = overallTimeout - overall.elapsed;
              if (remaining <= Duration.zero) {
                throw Exception(
                    'Nie udało się pobrać wszystkich stron obecności w wyznaczonym czasie.');
              }
              await openNextPage!(next)
                  .timeout(remaining < timeout ? remaining : timeout);
              if (_disposed) return;
              continue;
            }
            // Wynik i błąd zmieniamy razem, aby stary błąd nie zasłonił listy.
            _update(AttendanceLoadState(
              loading: false,
              status: 'Pobrano obecności.',
              snapshot: pages.length == 1
                  ? snapshot
                  : AttendanceSnapshot(
                      pageTitle: pages.first.pageTitle,
                      requiresLogin: false,
                      headers: pages.first.headers,
                      rows: rows.values.toList(),
                      pageUrl: pages.first.pageUrl,
                      isEmpty: rows.isEmpty,
                    ),
            ));
            return;
          }
        }

        await Future<void>.delayed(pollInterval);
      }

      if (_disposed) return;
      final title = lastSnapshot?.pageTitle ?? '';
      throw Exception(
        lastSnapshot?.requiresLogin == true
            ? 'Nie udało się zakończyć logowania do portalu UEK.'
            : 'Portal UEK nie zwrócił tabeli obecności w wyznaczonym czasie.'
                '${title.isEmpty ? '' : ' Ostatnia strona: $title.'}',
      );
    } catch (error) {
      _update(AttendanceLoadState(
        loading: false,
        status: 'Nie udało się pobrać obecności.',
        error: error.toString(),
      ));
    }
  }

  bool _isExpectedPage(AttendanceSnapshot snapshot, Uri? expected) {
    if (expected == null) return true;
    final actual = parseAttendancePageUrl(snapshot.pageUrl);
    return actual != null &&
        (actual.queryParameters['page'] ?? '1') ==
            (expected.queryParameters['page'] ?? '1');
  }

  void _update(AttendanceLoadState state) {
    if (_disposed) return;
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
