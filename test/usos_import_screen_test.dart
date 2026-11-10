import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:plan_zajec_uek/data/datasources/auth_service.dart';
import 'package:plan_zajec_uek/data/datasources/local_database.dart';
import 'package:plan_zajec_uek/data/datasources/plan_cas_session.dart';
import 'package:plan_zajec_uek/data/datasources/schedule_parser.dart';
import 'package:plan_zajec_uek/data/datasources/schedule_remote_datasource.dart';
import 'package:plan_zajec_uek/data/repositories/schedule_repository_impl.dart';
import 'package:plan_zajec_uek/domain/entities/schedule_entry.dart';
import 'package:plan_zajec_uek/domain/entities/usos_import.dart';
import 'package:plan_zajec_uek/presentation/providers/providers.dart';
import 'package:plan_zajec_uek/presentation/screens/groups/usos_import_screen.dart';

const _result = UsosImportResult(imported: [
  ResolvedUsosGroup(
    groupType: GroupType.dean,
    sourceLabel: 'ZIISS1-2311AD',
    scheduleCode: 'ZIISS1-2311AD',
    scheduleId: '123',
    scheduleLabel: 'ZIISS1-2311AD',
  ),
], unresolved: []);
const _sslError = 'net::ERR_SSL_PROTOCOL_ERROR';

class _Auth extends AuthService {
  @override
  Future<Credentials?> getCredentials() async =>
      const Credentials(username: 'test', password: 'test');
}

class _Repo extends ScheduleRepository {
  _Repo()
      : super(
          db: LocalDatabase(),
          remote: ScheduleRemoteDatasource(),
          parser: ScheduleParser(),
          auth: _Auth(),
        );

  late Completer<UsosImportResult> resolution = Completer<UsosImportResult>();
  int calls = 0;
  final scans = <UsosImportData>[];

  @override
  Future<UsosImportResult> resolveUsosGroups(UsosImportData data) {
    calls++;
    scans.add(data);
    return resolution.future;
  }
}

class _WebViews extends WebViewPlatform {
  late _Controller controller;
  late _Delegate delegate;

  void fail({bool mainFrame = true}) => delegate.error(WebResourceError(
        errorCode: -107,
        description: _sslError,
        isForMainFrame: mainFrame,
      ));

  @override
  PlatformWebViewController createPlatformWebViewController(
          PlatformWebViewControllerCreationParams params) =>
      controller = _Controller(params);

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
          PlatformWebViewWidgetCreationParams params) =>
      _WebWidget(params);

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
          PlatformNavigationDelegateCreationParams params) =>
      delegate = _Delegate(params);
}

class _WebWidget extends PlatformWebViewWidget {
  _WebWidget(super.params) : super.implementation();
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _Delegate extends PlatformNavigationDelegate {
  _Delegate(super.params) : super.implementation();
  late PageEventCallback finished;
  late WebResourceErrorCallback error;

  @override
  Future<void> setOnPageStarted(PageEventCallback callback) async {}
  @override
  Future<void> setOnPageFinished(PageEventCallback callback) async {
    finished = callback;
  }

  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback callback) async {
    error = callback;
  }
}

class _Controller extends PlatformWebViewController {
  _Controller(super.params) : super.implementation();
  String url = '';
  int requests = 0;
  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}
  @override
  Future<void> setBackgroundColor(Color color) async {}
  @override
  Future<void> setPlatformNavigationDelegate(
      PlatformNavigationDelegate delegate) async {}
  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    requests++;
    url = params.uri.toString();
  }

  @override
  Future<Object> runJavaScriptReturningResult(String script) async =>
      jsonEncode(script.contains('const rawText')
          ? {
              'url': url,
              'text': '',
              'rows': <String>[],
              'deanCodes': url.contains('grupyDziekanskie')
                  ? ['ZIISS1-2311AD']
                  : <String>[],
            }
          : {
              'isLogin': false,
              'hasLoginLink': false,
              'hasDeanGroupsHeading': url.contains('grupyDziekanskie'),
            });
}

void main() {
  late _WebViews web;
  late _Repo repo;
  late WebViewPlatform? previousPlatform;

  setUp(() {
    previousPlatform = WebViewPlatform.instance;
    web = _WebViews();
    WebViewPlatform.instance = web;
    repo = _Repo();
  });
  tearDown(() {
    if (previousPlatform != null) WebViewPlatform.instance = previousPlatform;
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authServiceProvider.overrideWithValue(_Auth()),
        scheduleRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(home: UsosImportScreen()),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> scan(WidgetTester tester) async {
    for (var page = 0; page < 3; page++) {
      web.delegate.finished(web.controller.url);
      await tester.pumpAndSettle();
    }
  }

  testWidgets('shows main-frame failures but ignores subresource errors',
      (tester) async {
    await open(tester);
    web.fail(mainFrame: false);
    await tester.pump();
    expect(find.textContaining(_sslError), findsNothing);
    web.fail();
    await tester.pump();
    expect(find.textContaining(_sslError), findsOneWidget);
  });

  testWidgets(
      'catalog failure retains USOS scan and retries without navigation',
      (tester) async {
    await open(tester);
    await scan(tester);
    repo.resolution.completeError(const PlanLoginException(
        'CAS nie zakończył logowania.',
        steps: ['CAS: POST → HTTP 200']));
    await tester.pumpAndSettle();
    expect(find.textContaining('Grupy zostały poprawnie pobrane z USOS'),
        findsOneWidget);
    expect(find.textContaining('CAS nie zakończył logowania.'), findsOneWidget);
    expect(find.textContaining('CAS: POST → HTTP 200'), findsOneWidget);
    expect(find.textContaining('Znalezione w USOS: 1'), findsOneWidget);
    expect(find.textContaining('Nie znaleziono dopasowań'), findsNothing);
    expect(find.textContaining('HTTP 500'), findsNothing);
    final requests = web.controller.requests;
    repo.resolution = Completer<UsosImportResult>();
    await tester.tap(find.text('Ponów dopasowanie do planu UEK'));
    await tester.pump();
    expect(repo.calls, 2);
    expect(identical(repo.scans[0], repo.scans[1]), isTrue);
    expect(web.controller.requests, requests);
    repo.resolution.complete(_result);
    await tester.pumpAndSettle();
    expect(find.text('Dodaj wybrane (1)'), findsOneWidget);
    expect(find.textContaining('awarii serwera'), findsNothing);
    expect(find.textContaining('CAS nie zakończył logowania.'), findsNothing);
  });

  testWidgets('valid catalog with no matches is distinct from catalog failure',
      (tester) async {
    await open(tester);
    repo.resolution
        .complete(const UsosImportResult(imported: [], unresolved: []));
    await scan(tester);
    expect(find.textContaining('Nie znaleziono dopasowań'), findsOneWidget);
    expect(find.textContaining('awarii serwera'), findsNothing);
    expect(find.text('Ponów dopasowanie do planu UEK'), findsOneWidget);
  });

  testWidgets('successful resolution clears errors received while matching',
      (tester) async {
    await open(tester);
    await scan(tester);
    web.fail();
    await tester.pump();
    expect(find.textContaining(_sslError), findsOneWidget);
    repo.resolution.complete(_result);
    await tester.pumpAndSettle();
    expect(find.textContaining(_sslError), findsNothing);
    expect(find.text('Dodaj wybrane (1)'), findsOneWidget);
  });

  testWidgets('late SSL errors do not overwrite results; retry exposes errors',
      (tester) async {
    await open(tester);
    repo.resolution.complete(_result);
    await scan(tester);
    web.fail();
    await tester.pumpAndSettle();
    expect(find.textContaining(_sslError), findsNothing);
    expect(find.text('ZIISS1-2311AD'), findsOneWidget);
    expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isTrue);
    expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNotNull);
    await tester.tap(find.byIcon(Icons.refresh_rounded));
    await tester.pumpAndSettle();
    web.fail();
    await tester.pump();
    expect(find.textContaining(_sslError), findsOneWidget);
    expect(find.text('Dodaj wybrane (1)'), findsNothing);
  });
}
