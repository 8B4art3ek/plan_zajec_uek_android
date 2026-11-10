import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plan_zajec_uek/core/refresh_settings.dart';
import 'package:plan_zajec_uek/core/theme/app_theme.dart';
import 'package:plan_zajec_uek/data/datasources/auth_service.dart';
import 'package:plan_zajec_uek/data/datasources/local_database.dart';
import 'package:plan_zajec_uek/data/datasources/schedule_parser.dart';
import 'package:plan_zajec_uek/data/datasources/schedule_remote_datasource.dart';
import 'package:plan_zajec_uek/data/repositories/schedule_repository_impl.dart';
import 'package:plan_zajec_uek/presentation/providers/providers.dart';
import 'package:plan_zajec_uek/presentation/screens/settings/custom_colors_screen.dart';

class _Repo extends ScheduleRepository {
  _Repo()
      : super(
            db: LocalDatabase(),
            remote: ScheduleRemoteDatasource(),
            parser: ScheduleParser(),
            auth: AuthService());
  final settings = <String, String>{};
  @override
  Future<String?> getAppSetting(String key) async => settings[key];
  @override
  Future<void> setAppSetting(String key, String value) async {
    settings[key] = value;
  }
}

void main() {
  test(
      'refresh validates saved intervals and combines interval with retry backoff',
      () {
    expect(RefreshSettings.parse(null), 60);
    expect(RefreshSettings.parse('3'), 60);
    expect(RefreshSettings.parse('0'), 0);
    expect(RefreshSettings.parse('15'), 15);
    final last = DateTime(2026, 11, 5, 12);
    expect(RefreshSettings.dueAt(0, last, last), isNull);
    expect(RefreshSettings.dueAt(60, last, null),
        last.add(const Duration(hours: 1)));
    final retry = last.add(const Duration(hours: 2));
    expect(RefreshSettings.dueAt(15, last, retry), retry);
    expect(RefreshSettings.dueAt(120, last, last), retry);
  });

  test(
      'custom colors persist, restore after restart and reset without changing base theme',
      () async {
    final repo = _Repo();
    ProviderContainer container() => ProviderContainer(
        overrides: [scheduleRepositoryProvider.overrideWithValue(repo)]);
    final first = container();
    await first.read(customThemeColorsProvider.future);
    await first
        .read(customThemeColorsProvider.notifier)
        .setColor('primary', Colors.red);
    first.dispose();
    final second = container();
    addTearDown(second.dispose);
    expect(
        (await second.read(customThemeColorsProvider.future))['primary']!
            .toARGB32(),
        Colors.red.toARGB32());
    await second.read(customThemeColorsProvider.notifier).reset();
    expect(second.read(customThemeColorsProvider).value, isEmpty);
    expect(repo.settings['theme_color_primary'], '');
  });

  test(
      'refresh selection updates background scheduler and rolls back on failure',
      () async {
    final repo = _Repo();
    final scheduled = <int>[];
    var fail = false;
    final container = ProviderContainer(overrides: [
      scheduleRepositoryProvider.overrideWithValue(repo),
      refreshSchedulerProvider.overrideWithValue((minutes) async {
        if (fail) throw StateError('Scheduler unavailable');
        scheduled.add(minutes);
      }),
    ]);
    addTearDown(container.dispose);
    expect(await container.read(refreshMinutesProvider.future), 60);
    await container.read(refreshMinutesProvider.notifier).setMinutes(15);
    await container.read(refreshMinutesProvider.notifier).setMinutes(0);
    expect(scheduled, [15, 0]);
    expect(await repo.automaticRefreshMinutes(), 0);
    expect(await repo.automaticRefreshDueAt(), isNull);
    fail = true;
    await expectLater(
        container.read(refreshMinutesProvider.notifier).setMinutes(120),
        throwsStateError);
    expect(await repo.automaticRefreshMinutes(), 0);
    expect(container.read(refreshMinutesProvider).value, 0);
  });

  test(
      'custom palette keeps text readable and switching base does not retain static colors',
      () {
    AppTheme.themeFor(AppThemeKind.custom,
        colors: {'primary': Colors.red, 'background': Colors.white});
    expect(AppColors.primary, Colors.red);
    expect(AppColors.brightness, Brightness.light);
    final contrast = (AppColors.surface.computeLuminance() + 0.05) /
        (AppColors.onSurface.computeLuminance() + 0.05);
    expect(contrast, greaterThan(4.5));
    AppTheme.themeFor(AppThemeKind.midnight);
    expect(AppColors.primary, const Color(0xFF6C63FF));
    expect(AppColors.brightness, Brightness.dark);
  });

  test('opposite background and surface colors keep both text areas readable',
      () {
    for (final pair in [
      (Colors.black, Colors.white),
      (Colors.white, Colors.black)
    ]) {
      AppTheme.themeFor(AppThemeKind.custom,
          colors: {'background': pair.$1, 'surface': pair.$2});
      for (final background in [AppColors.background, AppColors.surface]) {
        final a = background.computeLuminance();
        final b = AppColors.onSurface.computeLuminance();
        final ratio = a > b ? (a + 0.05) / (b + 0.05) : (b + 0.05) / (a + 0.05);
        expect(ratio, greaterThanOrEqualTo(4.5));
      }
    }
    AppTheme.themeFor(AppThemeKind.midnight);
  });

  test('saved custom theme survives preset selection and restarting', () async {
    final repo = _Repo();
    final container = ProviderContainer(
        overrides: [scheduleRepositoryProvider.overrideWithValue(repo)]);
    await container.read(customThemeColorsProvider.future);
    final custom = {
      'primary': const Color(0xFF008577),
      'secondary': const Color(0xFFD13A64),
      'background': Colors.white,
      'surface': const Color(0xFFF4F4F6)
    };
    await container.read(customThemeColorsProvider.notifier).saveTheme(custom);
    expect(container.read(appThemeProvider).value, AppThemeKind.custom);
    await container
        .read(appThemeProvider.notifier)
        .setTheme(AppThemeKind.graphite);
    AppTheme.themeFor(AppThemeKind.graphite, colors: custom);
    expect(AppColors.primary, const Color(0xFFE8B75C));
    container.dispose();
    final restarted = ProviderContainer(
        overrides: [scheduleRepositoryProvider.overrideWithValue(repo)]);
    addTearDown(restarted.dispose);
    expect(
        await restarted.read(appThemeProvider.future), AppThemeKind.graphite);
    final saved = await restarted.read(customThemeColorsProvider.future);
    await restarted
        .read(appThemeProvider.notifier)
        .setTheme(AppThemeKind.custom);
    AppTheme.themeFor(AppThemeKind.custom, colors: saved);
    expect(AppColors.primary.toARGB32(), custom['primary']!.toARGB32());
    expect(AppColors.background, Colors.white);
    AppTheme.themeFor(AppThemeKind.midnight);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('color palette fits narrow phones at text scale $scale',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = _Repo();
      await tester.pumpWidget(ProviderScope(
          overrides: [scheduleRepositoryProvider.overrideWithValue(repo)],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!),
            home: const CustomColorsScreen(),
          )));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kolor główny'));
      await tester.pumpAndSettle();
      expect(find.byType(Slider), findsNWidgets(3));
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Zapisz'));
      await tester.pumpAndSettle();
      expect(repo.settings['theme_color_primary'], isNotEmpty);
      expect(tester.takeException(), isNull);
    });
  }
}
