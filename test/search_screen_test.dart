import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:plan_zajec_uek/core/date_labels.dart';
import 'package:plan_zajec_uek/core/theme/app_theme.dart';
import 'package:plan_zajec_uek/data/datasources/lecturer_directory.dart';
import 'package:plan_zajec_uek/data/datasources/plan_directory.dart';
import 'package:plan_zajec_uek/domain/entities/schedule_entry.dart';
import 'package:plan_zajec_uek/presentation/providers/providers.dart';
import 'package:plan_zajec_uek/presentation/providers/search_providers.dart';
import 'package:plan_zajec_uek/presentation/screens/search/search_screen.dart';
import 'package:plan_zajec_uek/presentation/widgets/app_viewport.dart';
import 'package:plan_zajec_uek/presentation/widgets/schedule_entry_details_sheet.dart';

final _lecturer = PlanTarget(
    name: 'Wołoszyn Paweł, prof. UEK',
    uri: Uri.parse('https://planzajec.uek.krakow.pl/index.php?typ=N&id=1'),
    kind: PlanKind.lecturer);
final _room = PlanTarget(
    name: 'Biblioteka 425',
    uri: Uri.parse('https://planzajec.uek.krakow.pl/index.php?typ=S&id=2'),
    kind: PlanKind.room);
final _card = LecturerCard('e-Wizytówka: Paweł Wołoszyn',
    Uri.parse('https://e-uczelnia.uek.krakow.pl/course/view.php?id=1045'));
final _now = DateTime.now();
final _today = DateTime(_now.year, _now.month, _now.day);
final _entry = ScheduleEntry(
    id: '1',
    subject: 'Instrumentarium przetwarzania danych',
    classType: 'wykład',
    lecturer: 'prof. UEK dr hab. Paweł Wołoszyn',
    room: 'Biblioteka 425',
    date: _today,
    startTime: '16:45',
    endTime: '18:15',
    weekday: 'wtorek',
    durationHours: 2,
    groupId: '1',
    groupType: GroupType.dean);

class _Colors extends ClassTypeColorsNotifier {
  @override
  Future<Map<String, Color>> build() async => {};
}

Widget _app(Widget screen,
        {double scale = 1,
        GlobalKey? boundary,
        void Function(int)? onPeriod,
        List<ScheduleEntry>? targetEntries}) =>
    ProviderScope(
      overrides: [
        classTypeColorsProvider.overrideWith(_Colors.new),
        savedScheduleProvider.overrideWith((ref) async => [_entry]),
        planCatalogueProvider.overrideWith((ref, key) async =>
            PlanDirectoryPage(
                [key.$1 == PlanKind.lecturer ? _lecturer : _room], {})),
        targetScheduleProvider.overrideWith((ref, request) async {
          onPeriod?.call(request.$2);
          return targetEntries ?? [_entry];
        }),
        lecturerCardsProvider.overrideWith((ref, name) async => [_card]),
        lecturerContactProvider.overrideWith((ref, card) async =>
            LecturerContact(emails: ['pawel.woloszyn@uek.krakow.pl'])),
      ],
      child: MaterialApp(
          theme: AppTheme.themeFor(AppThemeKind.midnight),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: RepaintBoundary(
                  key: boundary, child: AppViewport(child: child!))),
          home: screen),
    );

void main() {
  setUpAll(() async {
    for (final entry in {
      'sans-serif': const String.fromEnvironment('PREVIEW_FONT'),
      'MaterialIcons': const String.fromEnvironment('PREVIEW_ICONS')
    }.entries) {
      if (entry.value.isNotEmpty) {
        await (FontLoader(entry.key)
              ..addFont(
                  File(entry.value).readAsBytes().then(ByteData.sublistView)))
            .load();
      }
    }
  });

  testWidgets('filters saved classes without Polish accents and clears search',
      (tester) async {
    await tester.pumpWidget(_app(const SearchScreen()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'woloszyn');
    await tester.pumpAndSettle();
    expect(find.text(_entry.subject), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'nieistniejący');
    await tester.pumpAndSettle();
    expect(find.text('Brak wyników.'), findsOneWidget);
    await tester.tap(find.byTooltip('Wyczyść'));
    await tester.pumpAndSettle();
    expect(find.text(_entry.subject), findsOneWidget);
  });

  testWidgets(
      'lecturer search opens contact details and full lecturer schedule',
      (tester) async {
    await tester.pumpWidget(_app(const SearchScreen(initialTab: 1)));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_lecturer.name));
    await tester.pumpAndSettle();
    expect(find.text('pawel.woloszyn@uek.krakow.pl'), findsOneWidget);
    expect(find.text('Seminaria i konsultacje'), findsNothing);
    await tester.tap(find.text('Plan zajęć prowadzącego'));
    await tester.pumpAndSettle();
    expect(find.text(_entry.subject), findsOneWidget);
    expect(
        find.text(
            '${DateFormat('dd.MM.yyyy').format(_today)} · ${polishWeekday(_today)}'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('room search opens room schedule', (tester) async {
    await tester.pumpWidget(
        _app(const SearchScreen(initialTab: 2, initialQuery: '425')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_room.name));
    await tester.pumpAndSettle();
    expect(find.byType(TargetScheduleScreen), findsOneWidget);
    expect(find.text(_entry.subject), findsOneWidget);
  });

  for (final target in [_room, _lecturer]) {
    testWidgets(
        '${target.kind.name} plan defaults to period 1 and refreshes selected period',
        (tester) async {
      final periods = <int>[];
      await tester.pumpWidget(
          _app(TargetScheduleScreen(target: target), onPeriod: periods.add));
      await tester.pumpAndSettle();
      expect(periods, [1]);
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Okres 4').last);
      await tester.pumpAndSettle();
      expect(periods, [1, 4]);
      await tester.tap(find.byTooltip('Odśwież plan'));
      await tester.pumpAndSettle();
      expect(periods, [1, 4, 4]);
      expect(find.text('Okres 4'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '${target.kind.name} plan includes past, present and future dates',
        (tester) async {
      await tester.pumpWidget(
          _app(TargetScheduleScreen(target: target), targetEntries: [
        _entry.copyWith(
            id: 'past',
            subject: 'Wczorajsze zajęcia',
            date: DateTime(_today.year, _today.month, _today.day - 1, 23, 59)),
        _entry.copyWith(
            id: 'today', subject: 'Dzisiejsze zajęcia', startTime: '00:01'),
        _entry.copyWith(
            id: 'future',
            subject: 'Jutrzejsze zajęcia',
            date: DateTime(_today.year, _today.month, _today.day + 1)),
      ]));
      await tester.pumpAndSettle();
      expect(find.text('Wczorajsze zajęcia'), findsOneWidget);
      expect(find.text('Dzisiejsze zajęcia'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Jutrzejsze zajęcia'), 150,
          scrollable: find
              .descendant(
                  of: find.byType(ListView), matching: find.byType(Scrollable))
              .first);
      expect(find.text('Jutrzejsze zajęcia'), findsOneWidget);
    });
  }

  testWidgets(
      'plan from class lecturer does not loop back through lecturer profile',
      (tester) async {
    await tester.pumpWidget(_app(LecturerScreen(name: _entry.lecturer)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plan zajęć prowadzącego'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_lecturer.name));
    await tester.pumpAndSettle();
    expect(find.byType(TargetScheduleScreen), findsOneWidget);
    expect(find.text(_entry.subject), findsOneWidget);
  });

  testWidgets('entry details expose lecturer and room actions', (tester) async {
    var tapped = false;
    await tester.pumpWidget(_app(Builder(
        builder: (context) => TextButton(
            onPressed: () => showScheduleEntryDetailsSheet(
                context: context,
                entry: _entry,
                onLecturerTap: () => tapped = true,
                onRoomTap: () {}),
            child: const Text('Szczegóły')))));
    await tester.tap(find.text('Szczegóły'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_entry.lecturer));
    await tester.pumpAndSettle();
    expect(tapped, isTrue);
    expect(find.text('Prowadzący'), findsNothing);
  });

  for (final size in [const Size(320, 640), const Size(740, 360)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('search and lecturer details fit $size at scale $scale',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        for (final screen in [
          const SearchScreen(),
          LecturerScreen(name: _entry.lecturer),
          TargetScheduleScreen(target: _room)
        ]) {
          await tester.pumpWidget(_app(screen, scale: scale));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      });
    }
  }

  testWidgets('optional search and contact previews', (tester) async {
    if (!const bool.fromEnvironment('WRITE_PREVIEWS')) return;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final screen in {
      'search': const SearchScreen(),
      'lecturer': LecturerScreen(name: _entry.lecturer)
    }.entries) {
      final key = GlobalKey();
      await tester.pumpWidget(_app(screen.value, boundary: key));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('build/ui-check').create(recursive: true);
        await File('build/ui-check/${screen.key}.png')
            .writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }
  });
}
