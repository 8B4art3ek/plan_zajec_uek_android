import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plan_zajec_uek/core/theme/app_theme.dart';
import 'package:plan_zajec_uek/data/datasources/app_update_service.dart';
import 'package:plan_zajec_uek/presentation/providers/app_update_provider.dart';
import 'package:plan_zajec_uek/presentation/screens/settings/app_updates_screen.dart';

void main() {
  for (final width in [320.0, 412.0, 800.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('update screen fits $width at text scale $scale',
          (tester) async {
        tester.view.physicalSize = Size(width, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final controller = AppUpdateController(
            AppUpdateService(), AppUpdatePlatform())
          ..checked = true
          ..installed =
              const InstalledApp('1.0.0', 1, 'com.example.plan_zajec_uek')
          ..release = AppRelease(
              version: '1.0.1',
              build: 2,
              notes:
                  'Aktualizacje bezpośrednio w aplikacji.\nSprawdzanie instalatora przed instalacją.',
              url: Uri.parse('https://github.com/'),
              size: 450000000,
              sha256: 'test');
        await tester.pumpWidget(ProviderScope(
          overrides: [appUpdateProvider.overrideWith((ref) => controller)],
          child: MaterialApp(
            theme: AppTheme.themeFor(AppThemeKind.midnight),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(scale),
                  padding: const EdgeInsets.only(bottom: 48)),
              child: child!,
            ),
            home: const AppUpdatesScreen(),
          ),
        ));
        await tester.pumpAndSettle();
        expect(find.text('Wersja 1.0.0'), findsOneWidget);
        expect(find.text('Wersja 1.0.0 (1)'), findsNothing);
        await tester.scrollUntilVisible(find.text('Pobierz aktualizację'), 150);
        await tester.ensureVisible(
            find.widgetWithText(FilledButton, 'Pobierz aktualizację'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final button = tester
            .getRect(find.widgetWithText(FilledButton, 'Pobierz aktualizację'));
        expect(button.bottom, lessThanOrEqualTo(652));
      });
    }
  }
}
