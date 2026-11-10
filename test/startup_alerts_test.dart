import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plan_zajec_uek/core/theme/app_theme.dart';
import 'package:plan_zajec_uek/data/datasources/app_update_service.dart';
import 'package:plan_zajec_uek/data/datasources/startup_service.dart';
import 'package:plan_zajec_uek/domain/entities/schedule_change.dart';
import 'package:plan_zajec_uek/presentation/widgets/app_viewport.dart';
import 'package:plan_zajec_uek/presentation/widgets/startup_alerts.dart';

void main() {
  testWidgets('group setup options fit a small screen with large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    GroupSetupChoice? selected;
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!),
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async =>
                        selected = await showGroupSetupChoice(context),
                    child: const Text('Otwórz'))))));
    await tester.tap(find.text('Otwórz'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Dodaj ręcznie po ID'));
    await tester.tap(find.text('Dodaj ręcznie po ID'));
    await tester.pumpAndSettle();
    expect(selected, GroupSetupChoice.manual);
  });
  for (final size in [const Size(320, 640), const Size(740, 360)]) {
    for (final news in [true, false]) {
      testWidgets(
          '${news ? 'release' : 'schedule'} alert scrolls at $size with large text',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        bool? confirmed;
        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.themeFor(AppThemeKind.midnight),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: AppViewport(child: child!)),
          home: Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () async {
                        confirmed = news
                            ? await showReleaseNews(
                                context,
                                StartupRelease(
                                    const InstalledApp('1.0.5', 6, 'test'),
                                    List.generate(
                                        20,
                                        (i) =>
                                            'Nowość $i: wygodniejsze korzystanie z planu zajęć i importu grup.')))
                            : await showScheduleChanges(
                                context,
                                List.generate(
                                    20,
                                    (i) => ScheduleChange(
                                        id: i,
                                        groupId: '1',
                                        subject:
                                            'Bezpieczeństwo systemów informatycznych zarządzania',
                                        description:
                                            'Zmieniono zajęcia\nPrzed: 20.10.2026 09:00–10:30, sala A\nTeraz: 20.10.2026 12:00–13:30, sala B',
                                        detectedAt: DateTime(2026, 10, 20))));
                      },
                      child: const Text('Otwórz')))),
        ));
        await tester.tap(find.text('Otwórz'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Rozumiem'));
        await tester.pumpAndSettle();
        expect(confirmed, isTrue);
        expect(find.byType(AlertDialog), findsNothing);
      });
    }
  }
}
