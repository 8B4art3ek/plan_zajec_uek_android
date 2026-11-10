import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plan_zajec_uek/data/datasources/auth_service.dart';
import 'package:plan_zajec_uek/data/datasources/local_database.dart';
import 'package:plan_zajec_uek/data/datasources/schedule_parser.dart';
import 'package:plan_zajec_uek/data/datasources/schedule_remote_datasource.dart';
import 'package:plan_zajec_uek/data/repositories/schedule_repository_impl.dart';
import 'package:plan_zajec_uek/domain/entities/group.dart';
import 'package:plan_zajec_uek/domain/entities/schedule_entry.dart';
import 'package:plan_zajec_uek/domain/entities/subject_filter.dart';
import 'package:plan_zajec_uek/presentation/providers/providers.dart';
import 'package:plan_zajec_uek/presentation/screens/settings/settings_screen.dart';

const _longName = 'Instrumentarium przetwarzania danych i systemy komputerowe';

class _Repo extends ScheduleRepository {
  _Repo()
      : super(
            db: LocalDatabase(),
            remote: ScheduleRemoteDatasource(),
            parser: ScheduleParser(),
            auth: AuthService());
  final saved = <SubjectFilter>[];
  final subjects = <String, List<String>>{
    '1': ['Matematyka', _longName],
    '2': ['Język angielski'],
  };
  bool failLoad = false;
  @override
  Future<List<Group>> getGroups() async => const [
        Group(groupId: '1', groupType: GroupType.dean, name: 'ZIISS1-2311AD'),
        Group(groupId: '2', groupType: GroupType.language, name: 'CJ-TEST'),
      ];
  @override
  Future<List<String>> getSubjectsForGroup(String groupId) async {
    if (failLoad) throw StateError('Offline');
    return subjects[groupId] ?? [];
  }

  @override
  Future<List<SubjectFilter>> getSubjectFilters() async => [...saved];
  @override
  Future<void> upsertSubjectFilter(SubjectFilter filter) async {
    saved.add(filter);
  }

  @override
  Future<bool> getHideReservations() async => false;
  @override
  Future<String?> getAppSetting(String key) async => null;
}

void main() {
  late _Repo repo;
  setUp(() => repo = _Repo());

  Future<void> open(WidgetTester tester, {double scale = 1}) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [scheduleRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!),
        home: SettingsScreen(),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Filtry planu'), 150,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Filtry planu'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Dodaj filtr'));
    await tester.pumpAndSettle();
  }

  Future<void> selectSubject(WidgetTester tester, String name) async {
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(name).last);
    await tester.pumpAndSettle();
  }

  testWidgets('selects a subject and saves a hidden filter for its group',
      (tester) async {
    await open(tester);
    expect(
        tester
            .widget<ElevatedButton>(
                find.widgetWithText(ElevatedButton, 'Zapisz'))
            .onPressed,
        isNull);
    await selectSubject(tester, 'Matematyka');
    await tester.tap(find.text('Zapisz'));
    await tester.pumpAndSettle();
    expect(repo.saved.single.subject, 'Matematyka');
    expect(repo.saved.single.groupId, '1');
    expect(repo.saved.single.isHidden, isTrue);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('changing group resets subject and lists only that group',
      (tester) async {
    await open(tester);
    await selectSubject(tester, 'Matematyka');
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('CJ-TEST').last);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<ElevatedButton>(
                find.widgetWithText(ElevatedButton, 'Zapisz'))
            .onPressed,
        isNull);
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    expect(find.text('Matematyka'), findsNothing);
    await tester.tap(find.text('Język angielski').last);
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(Switch)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zapisz'));
    await tester.pumpAndSettle();
    expect(repo.saved.single.groupId, '2');
    expect(repo.saved.single.subject, 'Język angielski');
    expect(repo.saved.single.isHidden, isFalse);
  });

  testWidgets('empty cached plan disables save', (tester) async {
    repo.subjects['1'] = [];
    await open(tester);
    expect(find.text('Brak zapisanych przedmiotów dla tej grupy.'),
        findsOneWidget);
    expect(
        tester
            .widget<ElevatedButton>(
                find.widgetWithText(ElevatedButton, 'Zapisz'))
            .onPressed,
        isNull);
  });

  testWidgets('failed subject load can be retried', (tester) async {
    repo.failLoad = true;
    await open(tester);
    expect(find.text('Nie udało się odczytać przedmiotów.'), findsOneWidget);
    repo.failLoad = false;
    await tester.tap(find.text('Ponów'));
    await tester.pumpAndSettle();
    await selectSubject(tester, 'Matematyka');
    expect(tester.takeException(), isNull);
  });

  testWidgets('long subject dropdown fits small phone with enlarged text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await open(tester, scale: 2);
    await tester
        .ensureVisible(find.byType(DropdownButtonFormField<String>).last);
    await selectSubject(tester, _longName);
    await tester.ensureVisible(find.text('Zapisz'));
    expect(tester.takeException(), isNull);
  });
}
