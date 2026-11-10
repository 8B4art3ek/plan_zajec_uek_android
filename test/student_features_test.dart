import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plan_zajec_uek/data/datasources/auth_service.dart';
import 'package:plan_zajec_uek/data/datasources/local_database.dart';
import 'package:plan_zajec_uek/data/datasources/schedule_parser.dart';
import 'package:plan_zajec_uek/data/datasources/schedule_remote_datasource.dart';
import 'package:plan_zajec_uek/data/repositories/schedule_repository_impl.dart';
import 'package:plan_zajec_uek/domain/entities/campus_trip.dart';
import 'package:plan_zajec_uek/domain/entities/schedule_entry.dart';
import 'package:plan_zajec_uek/domain/entities/university.dart';
import 'package:plan_zajec_uek/presentation/providers/providers.dart';
import 'package:plan_zajec_uek/presentation/screens/travel/travel_screen.dart';
import 'package:plan_zajec_uek/presentation/screens/university_screen.dart';
import 'package:plan_zajec_uek/main.dart' show SplashScreen;

class _Auth extends AuthService {
  _Auth({this.credentials});
  final Credentials? credentials;
  @override
  Future<Credentials?> getCredentials() async => credentials;
}

class _Repo extends ScheduleRepository {
  _Repo()
      : super(
            db: LocalDatabase(),
            remote: ScheduleRemoteDatasource(),
            parser: ScheduleParser(),
            auth: _Auth());
  final settings = <String, String>{};
  List<ScheduleEntry> entries = [];
  bool failSave = false;
  @override
  Future<String?> getAppSetting(String key) async => settings[key];
  @override
  Future<void> setAppSetting(String key, String value) async {
    if (failSave) throw StateError('Storage unavailable');
    settings[key] = value;
  }

  @override
  Future<List<ScheduleEntry>> getEntriesForDate(DateTime date) async => entries;
}

ScheduleEntry _entry(DateTime date, String time,
        {bool moved = false, String type = 'wykład'}) =>
    ScheduleEntry(
      id: time,
      subject: 'Przedmiot',
      classType: type,
      lecturer: '',
      room: '',
      date: date,
      startTime: time,
      endTime: '14:00',
      weekday: '',
      durationHours: 2,
      groupId: '1',
      groupType: GroupType.dean,
      isMoved: moved,
    );

void main() {
  for (final scenario in [
    (false, false, 'Uczelnie'),
    (false, true, 'Logowanie'),
    (true, false, 'Plan')
  ]) {
    testWidgets(
        'startup routes account=${scenario.$1} selection=${scenario.$2} to ${scenario.$3}',
        (tester) async {
      final repo = _Repo();
      if (scenario.$2) repo.settings[UniversityNotifier.settingKey] = 'uek';
      await tester.pumpWidget(ProviderScope(
          overrides: [
            scheduleRepositoryProvider.overrideWithValue(repo),
            authServiceProvider.overrideWithValue(_Auth(
                credentials: scenario.$1
                    ? const Credentials(username: 'test', password: 'test')
                    : null)),
          ],
          child: MaterialApp(home: SplashScreen(), routes: {
            '/university': (_) => const Scaffold(body: Text('Uczelnie')),
            '/login': (_) => const Scaffold(body: Text('Logowanie')),
            '/home': (_) => const Scaffold(body: Text('Plan')),
          })));
      await tester.pumpAndSettle();
      expect(find.text(scenario.$3), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  test(
      'new users choose a university and the choice persists independently of credentials',
      () async {
    final repo = _Repo();
    ProviderContainer create() => ProviderContainer(overrides: [
          scheduleRepositoryProvider.overrideWithValue(repo),
          authServiceProvider.overrideWithValue(_Auth())
        ]);
    final first = create();
    expect(await first.read(universityProvider.future), isNull);
    await first.read(universityProvider.notifier).select(University.uek);
    first.dispose();
    final restarted = create();
    addTearDown(restarted.dispose);
    expect(await restarted.read(universityProvider.future), University.uek);
  });

  test('existing UEK users retain settings and migrate without another setup',
      () async {
    final repo = _Repo()..settings['app_theme'] = 'graphite';
    final container = ProviderContainer(overrides: [
      scheduleRepositoryProvider.overrideWithValue(repo),
      authServiceProvider.overrideWithValue(_Auth(
          credentials: const Credentials(username: 'test', password: 'test')))
    ]);
    addTearDown(container.dispose);
    expect(await container.read(universityProvider.future), University.uek);
    expect(repo.settings['app_theme'], 'graphite');
    expect(repo.settings[UniversityNotifier.settingKey], 'uek');
    expect(University.fromStorage('unknown'), isNull);
  });

  test(
      'trip URLs encode locations and transmit date, time, arrival mode and transport filters',
      () {
    final uri = campusTripLink(
        origin: 'Ruczaj & test/#',
        destination: CampusDestination.railway,
        dateTime: DateTime(2026, 11, 6, 9, 20),
        arriveBy: true,
        transport: {TripTransport.train});
    expect(uri.scheme, 'https');
    expect(uri.host, 'jakdojade.pl');
    expect(uri.pathSegments, ['krakow', 'Ruczaj & test/#', 'Kraków Główny']);
    expect(uri.queryParameters['d'], '06.11.26');
    expect(uri.queryParameters['h'], '09:20');
    expect(uri.queryParameters['ia'], 'true');
    expect(uri.queryParameters['apv'], 'bus,microbus,tram');
    expect(uri.hasFragment, isFalse);
  });

  test(
      'every campus destination has a working link format with all modes allowed',
      () {
    for (final destination in CampusDestination.values) {
      final uri = campusTripLink(
          origin: 'Ruczaj',
          destination: destination,
          dateTime: DateTime(2026, 11, 6),
          arriveBy: false,
          transport: TripTransport.values.toSet());
      expect(uri.queryParameters['tn'], destination.queryName);
      expect(uri.queryParameters.containsKey('apv'), isFalse);
    }
    expect(
        () => campusTripLink(
            origin: '',
            destination: CampusDestination.campus,
            dateTime: DateTime.now(),
            arriveBy: false,
            transport: TripTransport.values.toSet()),
        throwsArgumentError);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets(
        'university choice fits a small phone at scale $scale and precedes login',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = _Repo();
      await tester.pumpWidget(ProviderScope(
          overrides: [
            scheduleRepositoryProvider.overrideWithValue(repo),
            authServiceProvider.overrideWithValue(_Auth())
          ],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!),
            home: const UniversityScreen(),
            routes: {'/login': (_) => const Scaffold(body: Text('Logowanie'))},
          )));
      await tester.pumpAndSettle();
      expect(find.text('Wybierz uczelnię'), findsOneWidget);
      expect(find.text('Logowanie'), findsNothing);
      await tester.scrollUntilVisible(find.text('Kontynuuj'), 150);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kontynuuj'));
      await tester.pumpAndSettle();
      expect(find.text('Logowanie'), findsOneWidget);
      expect(repo.settings[UniversityNotifier.settingKey], 'uek');
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'travel controls fit a small phone at scale $scale and launch a real planner link',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Uri? opened;
      await tester.pumpWidget(ProviderScope(
          overrides: [
            tripLauncherProvider.overrideWithValue((uri) async {
              opened = uri;
              return true;
            })
          ],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!),
            home: const TravelPlannerScreen(),
          )));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Ruczaj');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Szukaj w Jakdojade'), 180,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Szukaj w Jakdojade'));
      await tester.pumpAndSettle();
      expect(opened?.host, 'jakdojade.pl');
      expect(opened?.queryParameters['tn'], 'Rakowicka 27, Kraków');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('arrival shortcut ignores moved classes and reservations',
      (tester) async {
    final day = DateTime.now().add(const Duration(days: 3));
    final repo = _Repo()
      ..entries = [
        _entry(day, '08:00', moved: true),
        _entry(day, '07:00', type: 'rezerwacja'),
        _entry(day, '09:30')
      ];
    Uri? opened;
    await tester.pumpWidget(ProviderScope(overrides: [
      scheduleRepositoryProvider.overrideWithValue(repo),
      tripLauncherProvider.overrideWithValue((uri) async {
        opened = uri;
        return true;
      })
    ], child: const MaterialApp(home: TravelPlannerScreen())));
    await tester.enterText(find.byType(TextFormField), 'Ruczaj');
    await tester.ensureVisible(find.text('10 min przed pierwszymi zajęciami'));
    await tester.tap(find.text('10 min przed pierwszymi zajęciami'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Szukaj w Jakdojade'));
    await tester.tap(find.text('Szukaj w Jakdojade'));
    await tester.pumpAndSettle();
    expect(opened?.queryParameters['h'], '09:20');
    expect(opened?.queryParameters['ia'], 'true');
  });

  testWidgets('launch failures are recoverable without losing origin',
      (tester) async {
    var fail = true;
    await tester.pumpWidget(ProviderScope(
        overrides: [tripLauncherProvider.overrideWithValue((_) async => !fail)],
        child: const MaterialApp(home: TravelPlannerScreen())));
    await tester.enterText(find.byType(TextFormField), 'Ruczaj');
    await tester.ensureVisible(find.text('Szukaj w Jakdojade'));
    await tester.tap(find.text('Szukaj w Jakdojade'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Nie udało się otworzyć Jakdojade'),
        findsOneWidget);
    fail = false;
    await tester.ensureVisible(find.text('Szukaj w Jakdojade'));
    await tester.tap(find.text('Szukaj w Jakdojade'));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('Nie udało się otworzyć Jakdojade'), findsNothing);
  });
}
