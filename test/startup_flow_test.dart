import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:plan_zajec_uek/core/theme/app_theme.dart';
import 'package:plan_zajec_uek/core/app_identity.dart';
import 'package:plan_zajec_uek/data/datasources/app_update_service.dart';
import 'package:plan_zajec_uek/data/datasources/auth_service.dart';
import 'package:plan_zajec_uek/data/datasources/local_database.dart';
import 'package:plan_zajec_uek/data/datasources/schedule_parser.dart';
import 'package:plan_zajec_uek/data/datasources/schedule_remote_datasource.dart';
import 'package:plan_zajec_uek/data/datasources/startup_service.dart';
import 'package:plan_zajec_uek/data/repositories/schedule_repository_impl.dart';
import 'package:plan_zajec_uek/domain/entities/group.dart';
import 'package:plan_zajec_uek/domain/entities/schedule_entry.dart';
import 'package:plan_zajec_uek/domain/entities/schedule_change.dart';
import 'package:plan_zajec_uek/domain/entities/subject_filter.dart';
import 'package:plan_zajec_uek/data/datasources/plan_directory.dart';
import 'package:plan_zajec_uek/presentation/providers/search_providers.dart';
import 'package:plan_zajec_uek/presentation/screens/settings/settings_screen.dart';
import 'package:plan_zajec_uek/presentation/screens/groups/groups_screen.dart';
import 'package:plan_zajec_uek/presentation/screens/search/search_screen.dart';
import 'package:plan_zajec_uek/presentation/providers/providers.dart';
import 'package:plan_zajec_uek/presentation/providers/app_update_provider.dart';
import 'package:plan_zajec_uek/presentation/providers/startup_provider.dart';
import 'package:plan_zajec_uek/presentation/screens/login_screen.dart';
import 'package:plan_zajec_uek/presentation/screens/main_shell.dart';
import 'package:plan_zajec_uek/presentation/screens/groups/usos_import_screen.dart';
import 'package:plan_zajec_uek/presentation/widgets/app_viewport.dart';

class _Auth extends AuthService {
  bool saved = false;
  @override
  Future<Credentials?> getCredentials() async =>
      const Credentials(username: 'test', password: 'test');
  @override
  Future<void> saveCredentials(String username, String password) async {
    saved = true;
  }
}

class _Remote extends ScheduleRemoteDatasource {
  @override
  Future<void> verifyCredentials(
      {required String username, required String password}) async {}
}

class _Repo extends ScheduleRepository {
  _Repo(ScheduleRemoteDatasource remote, AuthService auth)
      : super(
            db: LocalDatabase(),
            remote: remote,
            parser: ScheduleParser(),
            auth: auth);
  final settings = <String, String>{};
  final changes = <ScheduleChange>[];
  final acknowledged = <int>[];
  final groups = <Group>[];
  final previewEntries = <ScheduleEntry>[];
  int refreshes = 0;
  bool offline = false;
  @override
  Future<String?> getAppSetting(String key) async => settings[key];
  @override
  Future<void> setAppSetting(String key, String value) async {
    settings[key] = value;
  }

  @override
  Future<List<Group>> getGroups() async => groups;
  @override
  Future<List<SubjectFilter>> getSubjectFilters() async => [];
  @override
  Future<bool> getHideReservations() async => false;
  @override
  Future<ScheduleRefreshResult> refreshAllGroups() async {
    refreshes++;
    if (offline) throw StateError('Offline');
    return ScheduleRefreshResult(changed: false, failures: []);
  }

  @override
  Future<List<ScheduleChange>> getPendingScheduleChanges() async =>
      [...changes];
  @override
  Future<void> acknowledgeScheduleChanges(List<int> ids) async {
    acknowledged.addAll(ids);
    changes.removeWhere((change) => ids.contains(change.id));
  }
}

class _Colors extends ClassTypeColorsNotifier {
  @override
  Future<Map<String, Color>> build() async => {};
}

class _Theme extends AppThemeNotifier {
  @override
  Future<AppThemeKind> build() async => AppThemeKind.midnight;
}

class _WebViews extends WebViewPlatform {
  @override
  PlatformWebViewController createPlatformWebViewController(
          PlatformWebViewControllerCreationParams params) =>
      _Controller(params);
  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
          PlatformWebViewWidgetCreationParams params) =>
      _WebWidget(params);
  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
          PlatformNavigationDelegateCreationParams params) =>
      _Delegate(params);
}

class _WebWidget extends PlatformWebViewWidget {
  _WebWidget(super.params) : super.implementation();
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _Delegate extends PlatformNavigationDelegate {
  _Delegate(super.params) : super.implementation();
  @override
  Future<void> setOnPageStarted(PageEventCallback callback) async {}
  @override
  Future<void> setOnPageFinished(PageEventCallback callback) async {}
  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback callback) async {}
}

class _Controller extends PlatformWebViewController {
  _Controller(super.params) : super.implementation();
  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}
  @override
  Future<void> setBackgroundColor(Color color) async {}
  @override
  Future<void> setPlatformNavigationDelegate(
      PlatformNavigationDelegate delegate) async {}
  @override
  Future<void> loadRequest(LoadRequestParams params) async {}
  @override
  Future<Object> runJavaScriptReturningResult(String script) async =>
      jsonEncode({
        'title': 'Moje obecności',
        'url': 'https://portal.uek.krakow.pl/dashboard/obecnosci/mojeObecnosci',
        'isLogin': false,
        'headers': ['Identyfikator', 'Status'],
        'rows': [
          ['Matematyka, CW, grupa 1', 'Zarejestrowano']
        ],
      });
}

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
  final previewKey = GlobalKey();
  Future<void> preview(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('WRITE_PREVIEWS')) return;
    await tester.runAsync(() => precacheImage(
        const AssetImage(appIconAsset), previewKey.currentContext!));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final image = await (previewKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary)
          .toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('build/ui-check').create(recursive: true);
      await File('build/ui-check/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  late _Auth auth;
  late _Remote remote;
  late _Repo repo;
  late ProviderContainer container;
  setUp(() {
    WebViewPlatform.instance = _WebViews();
    auth = _Auth();
    remote = _Remote();
    repo = _Repo(remote, auth);
    final updates = AppUpdateController(AppUpdateService(), AppUpdatePlatform())
      ..checked = true;
    container = ProviderContainer(overrides: [
      authServiceProvider.overrideWithValue(auth),
      remoteDatasourceProvider.overrideWithValue(remote),
      scheduleRepositoryProvider.overrideWithValue(repo),
      startupServiceProvider.overrideWithValue(StartupService(
          repo, () async => const InstalledApp('1.0.5', 6, 'test'))),
      appUpdateProvider.overrideWith((ref) => updates),
      appThemeProvider.overrideWith(_Theme.new),
      classTypeColorsProvider.overrideWith(_Colors.new),
      todayScheduleProvider.overrideWith((ref) async => repo.previewEntries),
      planCatalogueProvider
          .overrideWith((ref, _) async => const PlanDirectoryPage([], {})),
      savedScheduleProvider.overrideWith((ref) async => []),
      refreshInfoProvider.overrideWith((ref) async =>
          const RefreshInfo(lastRefreshAt: null, status: null, error: null)),
    ]);
  });
  tearDown(() {
    container.dispose();
    remote.close();
  });
  Widget app(Widget home, {double scale = 1}) => UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.themeFor(AppThemeKind.midnight),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: AppViewport(
                child: RepaintBoundary(key: previewKey, child: child!))),
        home: home,
        routes: {'/home': (_) => const MainShell()},
      ));

  testWidgets(
      'four tabs and disabled travel screen fit a small phone with enlarged text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    repo.settings[StartupService.seenBuildKey] = '6';
    await tester.pumpWidget(app(const MainShell(), scale: 2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dojazdy'));
    await tester.pumpAndSettle();
    expect(find.text('Wkrótce'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('Szukaj w Jakdojade'), findsNothing);
    expect(find.byType(NavigationDestination), findsNWidgets(4));
    expect(tester.takeException(), isNull);
    if (const bool.fromEnvironment('WRITE_PREVIEWS')) {
      await tester.pumpWidget(app(const MainShell()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Więcej').last);
      await tester.pumpAndSettle();
      await preview(tester, 'navigation-more');
      repo.previewEntries.add(ScheduleEntry(
          id: 'preview',
          subject: 'Programowanie komputerów',
          classType: 'ćwiczenia',
          lecturer: 'Prowadzący',
          room: 'Pawilon A, sala 118',
          date: DateTime.now(),
          startTime: '09:45',
          endTime: '11:15',
          weekday: '',
          durationHours: 2,
          groupId: '1',
          groupType: GroupType.dean));
      container.invalidate(todayScheduleProvider);
      await tester.tap(find.text('Plan'));
      await tester.pumpAndSettle();
      await preview(tester, 'navigation-plan');
    }
  });

  testWidgets('startup respects stored cooldown while retaining pending alerts',
      (tester) async {
    repo.settings[StartupService.seenBuildKey] = '6';
    repo.groups.add(const Group(groupId: '1', groupType: GroupType.dean));
    repo.settings[ScheduleRepository.nextRefreshAttemptKey] =
        DateTime.now().add(const Duration(minutes: 15)).toIso8601String();
    await tester.pumpWidget(app(const MainShell()));
    await tester.pumpAndSettle();
    expect(repo.refreshes, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('more menu opens plan tools and returns to the same section',
      (tester) async {
    repo.settings[StartupService.seenBuildKey] = '6';
    await tester.pumpWidget(app(const MainShell()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Więcej').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Moje grupy'));
    await tester.pumpAndSettle();
    expect(find.byType(GroupsScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Filtry planu'));
    await tester.pumpAndSettle();
    expect(find.byType(PlanFiltersScreen), findsOneWidget);
    expect(find.byTooltip('Dodaj filtr'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Plany sal'));
    await tester.tap(find.text('Plany sal'));
    await tester.pumpAndSettle();
    expect(
        tester.widget<SearchScreen>(find.byType(SearchScreen)).initialTab, 2);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Plany prowadzących'));
    await tester.tap(find.text('Plany prowadzących'));
    await tester.pumpAndSettle();
    expect(
        tester.widget<SearchScreen>(find.byType(SearchScreen)).initialTab, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'tablet rail retains selected section when switching and resizing',
      (tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    repo.settings[StartupService.seenBuildKey] = '6';
    await tester.pumpWidget(app(const MainShell()));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await tester.tap(find.byIcon(Icons.route_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Wkrótce'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.grid_view_outlined));
    await tester.pumpAndSettle();
    await preview(tester, 'navigation-tablet');
    await tester.tap(find.byIcon(Icons.route_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Wkrótce'), findsOneWidget);
    tester.view.physicalSize = const Size(360, 800);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.text('Wkrótce'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Dzisiaj'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'successful login offers setup and opens USOS only after selecting it',
      (tester) async {
    repo.settings[StartupService.seenBuildKey] = '5';
    await tester.pumpWidget(app(LoginScreen()));
    await tester.enterText(find.byType(TextFormField).at(0), 'test');
    await tester.enterText(find.byType(TextFormField).at(1), 'test');
    await tester.ensureVisible(find.text('Zaloguj się'));
    await tester.tap(find.text('Zaloguj się'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(auth.saved, isTrue);
    expect(find.text('Jak dodać grupy?'), findsOneWidget);
    expect(find.byType(UsosImportScreen), findsNothing);
    await tester.tap(find.text('Importuj z USOS'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(UsosImportScreen), findsOneWidget);
    expect(find.text('Co nowego w 1.0.5'), findsNothing);
    expect(container.read(pendingGroupSetupProvider), isFalse);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(UsosImportScreen), findsNothing);
    expect(find.byType(MainShell), findsOneWidget);
    expect(find.text('Co nowego w 1.0.5'), findsOneWidget);
    await tester.tap(find.text('Rozumiem'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'release news precedes schedule alert and both acknowledge only after confirmation',
      (tester) async {
    repo.settings[StartupService.seenBuildKey] = '5';
    repo.changes.add(ScheduleChange(
        id: 1,
        groupId: '1',
        subject: 'Matematyka',
        description: 'Sala A → Sala B',
        detectedAt: DateTime(2026, 10, 20)));
    await tester.pumpWidget(app(const MainShell()));
    await tester.pumpAndSettle();
    expect(find.text('Co nowego w 1.0.5'), findsOneWidget);
    expect(find.text('Zmiany w planie'), findsNothing);
    expect(repo.settings[StartupService.seenBuildKey], '5');
    await tester.tap(find.text('Rozumiem'));
    await tester.pumpAndSettle();
    expect(repo.settings[StartupService.seenBuildKey], '6');
    expect(find.text('Zmiany w planie'), findsOneWidget);
    expect(repo.acknowledged, isEmpty);
    await tester.tap(find.text('Rozumiem'));
    await tester.pumpAndSettle();
    expect(repo.acknowledged, [1]);
    expect(repo.changes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('manual setup opens groups without starting a USOS scan',
      (tester) async {
    repo.settings[StartupService.seenBuildKey] = '6';
    container.read(pendingGroupSetupProvider.notifier).state = true;
    await tester.pumpWidget(app(const MainShell()));
    await tester.pumpAndSettle();
    expect(find.text('Jak dodać grupy?'), findsOneWidget);
    expect(find.text('Importuj z USOS'), findsOneWidget);
    await tester.tap(find.text('Dodaj ręcznie po ID'));
    await tester.pumpAndSettle();
    expect(find.byType(UsosImportScreen), findsNothing);
    expect(find.text('Dodaj grupę dziekańską'), findsOneWidget);
    expect(container.read(pendingGroupSetupProvider), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'offline startup still shows changes already detected in background',
      (tester) async {
    repo.settings[StartupService.seenBuildKey] = '6';
    repo.groups.add(const Group(groupId: '1', groupType: GroupType.dean));
    repo.offline = true;
    repo.changes.add(ScheduleChange(
        id: 2,
        groupId: '1',
        subject: 'Matematyka',
        description: 'Zmiana sali',
        detectedAt: DateTime(2026, 10, 20)));
    await tester.pumpWidget(app(const MainShell()));
    await tester.pumpAndSettle();
    expect(repo.refreshes, 1);
    expect(find.text('Zmiana sali'), findsOneWidget);
    expect(container.read(isRefreshingProvider), isFalse);
    await tester.tap(find.text('Rozumiem'));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(repo.refreshes, 1);
  });
}
