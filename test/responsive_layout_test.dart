import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plan_zajec_uek/core/theme/app_theme.dart';
import 'package:plan_zajec_uek/domain/entities/group.dart';
import 'package:plan_zajec_uek/domain/entities/schedule_entry.dart';
import 'package:plan_zajec_uek/domain/entities/subject_filter.dart';
import 'package:plan_zajec_uek/presentation/providers/providers.dart';
import 'package:plan_zajec_uek/presentation/screens/home/home_screen.dart';
import 'package:plan_zajec_uek/presentation/screens/login_screen.dart';
import 'package:plan_zajec_uek/presentation/screens/attendance/attendance_screen.dart';
import 'package:plan_zajec_uek/data/datasources/attendance_parser.dart';
import 'package:plan_zajec_uek/presentation/screens/groups/groups_screen.dart';
import 'package:plan_zajec_uek/presentation/screens/settings/settings_screen.dart';
import 'package:plan_zajec_uek/presentation/widgets/app_viewport.dart';
import 'package:plan_zajec_uek/presentation/widgets/class_card.dart';
import 'package:plan_zajec_uek/presentation/widgets/event_editor_sheet.dart';
import 'package:plan_zajec_uek/presentation/widgets/schedule_entry_details_sheet.dart';

ScheduleEntry _entry(String id, String time) => ScheduleEntry(
    id: id,
    subject: 'Instrumentarium przetwarzania danych i systemy komputerowe',
    classType: 'Ćwiczenia e-learningowe',
    lecturer: 'prof. UEK dr hab. Prowadzący z długim nazwiskiem',
    room: 'Budynek biblioteki, sala 425',
    date: DateTime(2026, 10, 20),
    startTime: time,
    endTime: '18:15',
    weekday: 'wtorek',
    durationHours: 2,
    groupId: '1',
    groupType: GroupType.dean);
final _entries = [
  _entry('1', '09:00'),
  _entry('2', '10:45'),
  _entry('3', '10:45'),
  _entry('4', '10:45')
];

class _Colors extends ClassTypeColorsNotifier {
  @override
  Future<Map<String, Color>> build() async => {};
}

class _Groups extends GroupsNotifier {
  @override
  Future<List<Group>> build() async => [
        Group(
            groupId: '123',
            groupType: GroupType.dean,
            name: 'Informatyka stosowana - grupa z długą nazwą')
      ];
}

class _Filters extends SubjectFiltersNotifier {
  @override
  Future<List<SubjectFilter>> build() async => [];
}

class _Hide extends HideReservationsNotifier {
  @override
  Future<bool> build() async => false;
}

class _Theme extends AppThemeNotifier {
  @override
  Future<AppThemeKind> build() async => AppThemeKind.midnight;
}

class _Refresh extends RefreshMinutesNotifier {
  @override
  Future<int> build() async => 60;
}

Widget _app(Widget home, double scale, GlobalKey key, {double keyboard = 0}) =>
    ProviderScope(
      overrides: [
        todayScheduleProvider.overrideWith((ref) async => _entries),
        selectedDateProvider.overrideWith((ref) => DateTime(2026, 10, 20)),
        refreshInfoProvider.overrideWith((ref) async =>
            const RefreshInfo(lastRefreshAt: null, status: null, error: null)),
        classTypeColorsProvider.overrideWith(_Colors.new),
        groupsProvider.overrideWith(_Groups.new),
        subjectFiltersProvider.overrideWith(_Filters.new),
        hideReservationsProvider.overrideWith(_Hide.new),
        appThemeProvider.overrideWith(_Theme.new),
        refreshMinutesProvider.overrideWith(_Refresh.new),
      ],
      child: MaterialApp(
        theme: AppTheme.themeFor(AppThemeKind.midnight),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              padding: EdgeInsets.fromLTRB(
                  MediaQuery.sizeOf(context).width >
                          MediaQuery.sizeOf(context).height
                      ? 24
                      : 0,
                  24,
                  MediaQuery.sizeOf(context).width >
                          MediaQuery.sizeOf(context).height
                      ? 24
                      : 0,
                  48),
              viewInsets: EdgeInsets.only(bottom: keyboard)),
          child: RepaintBoundary(key: key, child: AppViewport(child: child!)),
        ),
        home: home,
      ),
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
  for (final size in [
    const Size(320, 640),
    const Size(360, 800),
    const Size(740, 360),
    const Size(1024, 768)
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('plan and settings fit $size at scale $scale',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        for (final screen in [
          HomeScreen(),
          GroupsScreen(),
          SettingsScreen(),
          const PlanFiltersScreen(),
          const RefreshSettingsScreen(),
          ClassTypeColorsScreen(),
          LoginScreen(),
          AttendanceSubjectScreen(
              subject: AttendanceSubject(
                  name: _entries.first.subject,
                  records: const [
                AttendanceRecord(
                    subjectName: 'Instrumentarium',
                    classType: 'CW',
                    classDetails: 'CW, grupa 12',
                    openedAt: '20.10.2026 12:00:00',
                    registeredAt: '20.10.2026 12:05:00',
                    status: 'Zarejestrowano'),
              ]))
        ]) {
          final key = GlobalKey();
          await tester.pumpWidget(_app(screen, scale, key));
          await tester.pumpAndSettle();
          if (screen is HomeScreen) {
            final title = tester.getRect(find.text('Plan dnia'));
            final subtitle =
                tester.getRect(find.text('Ostatnia aktualizacja: brak'));
            final search = tester.getRect(find.byIcon(Icons.search_rounded));
            expect(title.center.dy, closeTo(search.center.dy, 0.5));
            expect(subtitle.top, closeTo(title.bottom, 0.5));
          }
          if (const bool.fromEnvironment('WRITE_PREVIEWS') &&
              screen is SettingsScreen &&
              size.width == 360 &&
              scale == 1) {
            await tester.runAsync(() async {
              final image = await (key.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
              final bytes =
                  await image.toByteData(format: ui.ImageByteFormat.png);
              await Directory('build/ui-check').create(recursive: true);
              await File('build/ui-check/more.png')
                  .writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          if (screen is GroupsScreen ||
              screen is SettingsScreen ||
              screen is ClassTypeColorsScreen) {
            await tester.drag(
                find.byType(ListView).first, const Offset(0, -1500));
            await tester.pumpAndSettle();
          }
          expect(tester.takeException(), isNull,
              reason: screen.runtimeType.toString());
          if (const bool.fromEnvironment('WRITE_PREVIEWS') &&
              screen is HomeScreen &&
              size.width == 360 &&
              scale == 1) {
            await tester.runAsync(() async {
              final image = await (key.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
              final bytes =
                  await image.toByteData(format: ui.ImageByteFormat.png);
              await Directory('build/ui-check').create(recursive: true);
              await File('build/ui-check/plan.png')
                  .writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          await tester.pumpWidget(const SizedBox());
        }
      });
    }
  }

  testWidgets('class text has equal top and bottom spacing', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Align(
                alignment: Alignment.topCenter,
                child: ClassCard(
                    entry: _entries.first, margin: EdgeInsets.zero)))));
    final card = tester.getRect(find
        .descendant(
            of: find.byType(ClassCard), matching: find.byType(Container))
        .first);
    final title = tester.getRect(find.text(_entries.first.subject));
    final room = tester.getRect(find.text(_entries.first.room));
    expect((title.top - card.top) - (card.bottom - room.bottom), closeTo(0, 1));
  });

  testWidgets('details and event form scroll above keyboard on a small phone',
      (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final home = Consumer(
        builder: (context, ref, _) => Scaffold(
                body: Column(children: [
              TextButton(
                  onPressed: () => showScheduleEntryDetailsSheet(
                      context: context, entry: _entries.first),
                  child: const Text('Details')),
              TextButton(
                  onPressed: () =>
                      showUserEventSheet(context: context, ref: ref),
                  child: const Text('Event')),
            ])));
    await tester.pumpWidget(_app(home, 2, GlobalKey(), keyboard: 180));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    Navigator.of(tester.element(find.text(_entries.first.subject))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Event'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Zapisz'), 150,
        scrollable: find.byType(Scrollable).last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getRect(find.widgetWithText(ElevatedButton, 'Zapisz')).bottom,
        lessThanOrEqualTo(300));
  });
}
