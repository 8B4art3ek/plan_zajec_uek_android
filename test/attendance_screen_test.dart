import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plan_zajec_uek/data/datasources/auth_service.dart';
import 'package:plan_zajec_uek/presentation/providers/providers.dart';
import 'package:plan_zajec_uek/presentation/screens/attendance/attendance_screen.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

const _subject = 'Instrumentarium przetwarzania danych';
final _result = {
  'title': 'Moje obecności',
  'isLogin': false,
  'headers': ['Identyfikator', 'Status'],
  'rows': [
    ['$_subject, CW, grupa 1', 'Zarejestrowano'],
  ],
};

class _TestAuthService extends AuthService {
  @override
  Future<Credentials?> getCredentials() async =>
      const Credentials(username: 'test', password: 'test');
}

class _TestWebViewPlatform extends WebViewPlatform {
  _TestWebViewPlatform(
      {this.simulateLogin = false, this.failFirstLoad = false, this.result});

  final bool simulateLogin;
  final bool failFirstLoad;
  final Map<String, Object?>? result;
  late _TestWebViewController controller;

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) =>
      controller = _TestWebViewController(params)
        ..simulateLogin = simulateLogin
        ..failFirstLoad = failFirstLoad
        ..result = result ?? _result;

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) =>
      _TestWebViewWidget(params);
}

class _TestWebViewWidget extends PlatformWebViewWidget {
  _TestWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _TestWebViewController extends PlatformWebViewController {
  _TestWebViewController(super.params) : super.implementation();

  int loads = 0;
  String loadedUrl = '';
  int reads = 0;
  int logins = 0;
  bool failFirstLoad = false;
  bool simulateLogin = false;
  Map<String, Object?> result = _result;

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {}

  @override
  Future<void> setBackgroundColor(Color color) async {}

  @override
  Future<void> clearCache() async {}

  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    loads++;
    loadedUrl = params.uri.toString();
    if (failFirstLoad && loads == 1) throw StateError('Network unavailable');
  }

  @override
  Future<Object> runJavaScriptReturningResult(String javaScript) async {
    if (javaScript.contains('HTMLFormElement.prototype.submit.call(form)')) {
      logins++;
      return true;
    }
    reads++;
    if (simulateLogin && reads < 5) {
      return jsonEncode({
        'title': 'Logowanie',
        'documentId': 'login-1',
        'isLogin': reads == 2 || reads == 3,
        'headers': [],
        'rows': [],
      });
    }
    return jsonEncode({...result, 'url': loadedUrl});
  }
}

Widget _app(Widget home) => ProviderScope(
      overrides: [authServiceProvider.overrideWithValue(_TestAuthService())],
      child: MaterialApp(home: home),
    );

void main() {
  testWidgets(
      'expands newest semester and keeps older subject details separate',
      (tester) async {
    final platform = _TestWebViewPlatform(result: {
      ..._result,
      'rows': [
        ['$_subject, CW, grupa 1\n25/26L - MAT', 'Brak obecności'],
        ['$_subject, LAB, grupa 2\n26/27Z - MAT', 'Zarejestrowano'],
      ],
    });
    WebViewPlatform.instance = platform;
    await tester.pumpWidget(_app(AttendanceScreen()));
    await tester.pumpAndSettle();
    expect(find.text(_subject), findsOneWidget);
    expect(find.text('Semestr zimowy 2026/2027'), findsOneWidget);
    await tester.tap(find.text(_subject));
    await tester.pumpAndSettle();
    expect(find.text('LAB, grupa 2 · 26/27Z - MAT'), findsOneWidget);
    expect(find.textContaining('CW, grupa 1'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Semestr letni 2025/2026'));
    await tester.pumpAndSettle();
    expect(find.text(_subject), findsNWidgets(2));
    await tester.tap(find.text(_subject).last);
    await tester.pumpAndSettle();
    expect(find.text('CW, grupa 1 · 25/26L - MAT'), findsOneWidget);
    expect(find.textContaining('LAB, grupa 2'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('loads attendance on startup while the tab is still hidden',
      (tester) async {
    final platform = _TestWebViewPlatform(simulateLogin: true);
    WebViewPlatform.instance = platform;
    final tab = ValueNotifier(0);
    addTearDown(tab.dispose);
    await tester.pumpWidget(_app(ValueListenableBuilder<int>(
      valueListenable: tab,
      builder: (context, index, _) => IndexedStack(
        index: index,
        children: [const Text('Plan dnia'), AttendanceScreen()],
      ),
    )));

    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
    tab.value = 1;
    await tester.pumpAndSettle();

    expect(find.text(_subject), findsOneWidget);
    expect(find.text('Nie udało się pobrać obecności.'), findsNothing);
    expect(platform.controller.loads, 1);
    expect(platform.controller.logins, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('one refresh displays attendance after an initial load error',
      (tester) async {
    final platform = _TestWebViewPlatform(failFirstLoad: true);
    WebViewPlatform.instance = platform;
    await tester.pumpWidget(_app(AttendanceScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Nie udało się pobrać danych'), findsOneWidget);

    await tester.tap(find.byTooltip('Odśwież obecności'));
    await tester.pumpAndSettle();

    expect(find.text(_subject), findsOneWidget);
    expect(find.text('Nie udało się pobrać obecności.'), findsNothing);
    expect(platform.controller.loads, 2);
    expect(tester.takeException(), isNull);
  });
}
