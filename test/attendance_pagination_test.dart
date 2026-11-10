import 'package:flutter_test/flutter_test.dart';
import 'package:plan_zajec_uek/data/datasources/attendance_loader.dart';
import 'package:plan_zajec_uek/data/datasources/attendance_parser.dart';
import 'package:plan_zajec_uek/data/datasources/auth_service.dart';

const _url = 'https://portal.uek.krakow.pl/dashboard/obecnosci/mojeObecnosci';

AttendanceSnapshot _page(int number, {String? next, List<String>? headers}) =>
    AttendanceSnapshot(
      pageTitle: 'Moje obecności',
      pageUrl: '$_url?page=$number',
      requiresLogin: false,
      headers: headers ?? ['Identyfikator', 'Status', 'Termin otwarcia'],
      rows: [
        ['Przedmiot, CW, grupa 1', 'Zarejestrowano', '2026-11-0$number'],
        ['Inny przedmiot, WYK, grupa 2', 'Zarejestrowano', '2026-10-01'],
      ],
      nextPageUrl: next,
    );

AttendanceLoader _loader({
  required Future<AttendanceSnapshot> Function() read,
  required Future<void> Function(Uri) next,
  Future<void> Function(bool)? open,
  int maxPages = 500,
}) =>
    AttendanceLoader(
      readCredentials: () async =>
          const Credentials(username: 'a', password: 'b'),
      openPage: open ?? (_) async {},
      firstPage: Uri.parse(_url),
      openNextPage: next,
      readSnapshot: read,
      submitLogin: (_) async => true,
      maxPages: maxPages,
      pollInterval: const Duration(milliseconds: 1),
      timeout: const Duration(milliseconds: 200),
    );

void main() {
  test('merges all pages, deduplicates rows and ignores stale documents',
      () async {
    var page = 1;
    var stale = false;
    var staleReads = 0;
    final opened = <int>[];
    final states = <AttendanceLoadState>[];
    final loader = _loader(
      read: () async {
        if (stale) {
          stale = false;
          staleReads++;
          return _page(page - 1, next: '$_url?page=$page');
        }
        return _page(page, next: page < 3 ? '$_url?page=${page + 1}' : null);
      },
      next: (url) async {
        page = int.parse(url.queryParameters['page']!);
        opened.add(page);
        stale = true;
      },
    );
    addTearDown(loader.dispose);
    loader.addListener(() => states.add(loader.state));
    await loader.load();
    expect(opened, [2, 3]);
    expect(staleReads, 2);
    expect(loader.state.error, isNull);
    expect(loader.state.snapshot!.rows, hasLength(4));
    expect(
        states
            .where((state) => state.loading)
            .every((state) => state.snapshot == null),
        isTrue);
    expect(states.map((state) => state.status),
        contains('Pobieram obecności: strona 3.'));
  });

  test('refresh starts at page one and replaces the previous result', () async {
    var page = 1;
    var refresh = false;
    final loader = _loader(
      open: (force) async {
        page = 1;
        refresh = force;
      },
      read: () async =>
          _page(page, next: !refresh && page == 1 ? '$_url?page=2' : null),
      next: (_) async {
        page = 2;
      },
    );
    addTearDown(loader.dispose);
    await loader.load();
    expect(loader.state.snapshot!.rows, hasLength(3));
    await loader.load(forceReload: true);
    expect(loader.state.snapshot!.rows, hasLength(2));
    expect(page, 1);
  });

  test('failure on a later page does not publish a partial list', () async {
    final loader = _loader(
      read: () async => _page(1, next: '$_url?page=2'),
      next: (_) async => throw StateError('Network unavailable'),
    );
    addTearDown(loader.dispose);
    await loader.load();
    expect(loader.state.loading, isFalse);
    expect(loader.state.error, isNotNull);
    expect(loader.state.snapshot, isNull);
  });

  for (final next in [
    'https://example.com/?page=2',
    '$_url?page=3',
    '$_url?page=1',
    '$_url?page=-2',
  ]) {
    test('rejects invalid pagination link $next', () async {
      var navigated = false;
      final loader = _loader(
        read: () async => _page(1, next: next),
        next: (_) async {
          navigated = true;
        },
      );
      addTearDown(loader.dispose);
      await loader.load();
      expect(navigated, isFalse);
      expect(loader.state.error, isNotNull);
      expect(loader.state.snapshot, isNull);
    });
  }

  test('page limit fails rather than presenting incomplete data', () async {
    final loader = _loader(
      read: () async => _page(1, next: '$_url?page=2'),
      next: (_) async => fail('Must not navigate'),
      maxPages: 1,
    );
    addTearDown(loader.dispose);
    await loader.load();
    expect(loader.state.error, isNotNull);
    expect(loader.state.snapshot, isNull);
  });

  test('pagination URLs stay on the authenticated attendance endpoint', () {
    expect(parseAttendancePageUrl('$_url?page=2'), isNotNull);
    for (final value in [
      'http://portal.uek.krakow.pl/dashboard/obecnosci/mojeObecnosci?page=2',
      '$_url?page=2&page=3',
      '$_url?page=0',
      '$_url?page=%xx',
      '$_url/other?page=2',
      'https://user@portal.uek.krakow.pl/dashboard/obecnosci/mojeObecnosci?page=2',
    ]) {
      expect(parseAttendancePageUrl(value), isNull, reason: value);
    }
  });
}
