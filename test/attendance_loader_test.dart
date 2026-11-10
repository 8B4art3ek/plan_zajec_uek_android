import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:plan_zajec_uek/data/datasources/attendance_loader.dart';
import 'package:plan_zajec_uek/data/datasources/attendance_parser.dart';
import 'package:plan_zajec_uek/data/datasources/auth_service.dart';

const _credentials = Credentials(username: 'test', password: 'test');
const _transition = AttendanceSnapshot(
  pageTitle: 'Przekierowanie',
  requiresLogin: false,
  headers: [],
  rows: [],
);
const _login = AttendanceSnapshot(
  pageTitle: 'Logowanie',
  pageUrl: 'https://logowanie.uek.krakow.pl/cas/login',
  documentId: 'login-1',
  requiresLogin: true,
  headers: [],
  rows: [],
);
const _result = AttendanceSnapshot(
  pageTitle: 'Moje obecności',
  requiresLogin: false,
  headers: ['Identyfikator', 'Status'],
  rows: [
    ['Instrumentarium przetwarzania danych, CW, grupa 1', 'Zarejestrowano'],
  ],
);

AttendanceLoader _loader({
  required Future<AttendanceSnapshot> Function() readSnapshot,
  Future<void> Function(bool)? openPage,
  Future<bool> Function(Credentials)? submitLogin,
  Duration timeout = const Duration(seconds: 1),
}) {
  return AttendanceLoader(
    readCredentials: () async => _credentials,
    openPage: openPage ?? (_) async {},
    readSnapshot: readSnapshot,
    submitLogin: submitLogin ?? (_) async => true,
    pollInterval: const Duration(milliseconds: 1),
    timeout: timeout,
  );
}

void main() {
  test('first load survives login, redirects and delayed table without refresh',
      () async {
    var reads = 0;
    var logins = 0;
    var pageLoads = 0;
    final states = <AttendanceLoadState>[];
    final loader = _loader(
      openPage: (_) async => pageLoads++,
      readSnapshot: () async {
        switch (reads++) {
          case 0:
            return _transition;
          case 1:
          case 2:
            return _login;
          case 3:
            throw StateError('Document is navigating');
          case 4:
            return _transition;
          default:
            return _result;
        }
      },
      submitLogin: (_) async {
        logins++;
        return true;
      },
    );
    addTearDown(loader.dispose);
    loader.addListener(() => states.add(loader.state));

    await loader.load();

    expect(pageLoads, 1);
    expect(logins, 1);
    expect(states.every((state) => state.error == null), isTrue);
    expect(loader.state.loading, isFalse);
    expect(loader.state.snapshot, same(_result));
  });

  test('waits for table rows loaded after the initial page', () async {
    var reads = 0;
    final loader = _loader(readSnapshot: () async {
      if (reads++ < 3) {
        return const AttendanceSnapshot(
          pageTitle: 'Moje obecności',
          requiresLogin: false,
          headers: ['Identyfikator', 'Status'],
          rows: [],
        );
      }
      return _result;
    });
    addTearDown(loader.dispose);

    await loader.load();

    expect(reads, 4);
    expect(loader.state.snapshot?.subjects.single.name,
        'Instrumentarium przetwarzania danych');
    expect(loader.state.error, isNull);
  });

  test('one refresh clears previous error and publishes the downloaded list',
      () async {
    var pageLoads = 0;
    final loader = _loader(
      openPage: (forceReload) async {
        if (pageLoads++ == 0) throw StateError('Network unavailable');
        expect(forceReload, isTrue);
      },
      readSnapshot: () async => _result,
    );
    addTearDown(loader.dispose);

    await loader.load();
    expect(loader.state.error, isNotNull);
    await loader.load(forceReload: true);

    expect(pageLoads, 2);
    expect(loader.state.status, 'Pobrano obecności.');
    expect(loader.state.error, isNull);
    expect(loader.state.loading, isFalse);
    expect(loader.state.snapshot?.subjects, hasLength(1));
  });

  test('overlapping refresh requests share a single download', () async {
    final pending = Completer<AttendanceSnapshot>();
    var pageLoads = 0;
    final loader = _loader(
      openPage: (_) async => pageLoads++,
      readSnapshot: () => pending.future,
    );
    addTearDown(loader.dispose);

    final first = loader.load();
    final second = loader.load(forceReload: true);
    expect(identical(first, second), isTrue);
    pending.complete(_result);
    await Future.wait([first, second]);

    expect(pageLoads, 1);
    expect(loader.state.error, isNull);
    expect(loader.state.snapshot, same(_result));
  });

  test('accepts an explicitly empty attendance table', () async {
    final loader = _loader(
      readSnapshot: () async => const AttendanceSnapshot(
        pageTitle: 'Moje obecności',
        requiresLogin: false,
        headers: ['Identyfikator', 'Status'],
        rows: [],
        isEmpty: true,
      ),
    );
    addTearDown(loader.dispose);

    await loader.load();

    expect(loader.state.loading, isFalse);
    expect(loader.state.error, isNull);
    expect(loader.state.snapshot?.subjects, isEmpty);
  });

  test('ends loading if the portal never returns attendance data', () async {
    final loader = _loader(
      readSnapshot: () async => _transition,
      timeout: const Duration(milliseconds: 20),
    );
    addTearDown(loader.dispose);

    await loader.load();

    expect(loader.state.loading, isFalse);
    expect(loader.state.error, contains('wyznaczonym czasie'));
    expect(loader.state.snapshot, isNull);
  });

  test('does not publish a result after leaving the screen', () async {
    final pending = Completer<AttendanceSnapshot>();
    final reading = Completer<void>();
    var notifications = 0;
    final loader = _loader(readSnapshot: () {
      reading.complete();
      return pending.future;
    });
    loader.addListener(() => notifications++);

    final loading = loader.load();
    await reading.future;
    loader.dispose();
    final before = notifications;
    pending.complete(_result);
    await loading;

    expect(notifications, before);
    expect(loader.state.snapshot, isNull);
  });
}
