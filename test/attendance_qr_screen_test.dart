import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:plan_zajec_uek/data/datasources/auth_service.dart';
import 'package:plan_zajec_uek/presentation/providers/providers.dart';
import 'package:plan_zajec_uek/presentation/screens/attendance/attendance_qr_screen.dart';

const _url = 'https://portal.uek.krakow.pl/obecnosc/123456789';

class _Camera extends MobileScannerPlatform {
  final captures = StreamController<BarcodeCapture?>.broadcast();
  bool deny = false;
  int stops = 0;
  final zooms = <double>[];
  @override
  Future<void> setZoomScale(double zoomScale) async => zooms.add(zoomScale);
  @override
  Stream<BarcodeCapture?> get barcodesStream => captures.stream;
  @override
  Stream<TorchState> get torchStateStream => const Stream.empty();
  @override
  Stream<double> get zoomScaleStateStream => const Stream.empty();
  @override
  Future<MobileScannerViewAttributes> start(StartOptions options) async {
    if (deny) {
      throw const MobileScannerException(
          errorCode: MobileScannerErrorCode.permissionDenied);
    }
    return const MobileScannerViewAttributes(
        cameraDirection: CameraFacing.back,
        currentTorchMode: TorchState.off,
        size: Size(640, 480));
  }

  @override
  Widget buildCameraView() => const ColoredBox(color: Colors.black);
  @override
  Future<void> updateScanWindow(Rect? window) async {}
  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> dispose() async {}
}

class _Auth extends AuthService {
  @override
  Future<Credentials?> getCredentials() async =>
      const Credentials(username: 'test', password: 'test');
}

class _Web extends WebViewPlatform {
  late _Controller controller;
  late _Delegate delegate;
  @override
  PlatformWebViewController createPlatformWebViewController(
          PlatformWebViewControllerCreationParams params) =>
      controller = _Controller(params);
  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
          PlatformWebViewWidgetCreationParams params) =>
      _Widget(params);
  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
          PlatformNavigationDelegateCreationParams params) =>
      delegate = _Delegate(params);
}

class _Widget extends PlatformWebViewWidget {
  _Widget(super.params) : super.implementation();
  @override
  Widget build(BuildContext context) => const Text('Strona rejestracji UEK');
}

class _Delegate extends PlatformNavigationDelegate {
  _Delegate(super.params) : super.implementation();
  late PageEventCallback finished;
  late NavigationRequestCallback navigate;
  @override
  Future<void> setOnPageStarted(PageEventCallback callback) async {}
  @override
  Future<void> setOnPageFinished(PageEventCallback callback) async {
    finished = callback;
  }

  @override
  Future<void> setOnNavigationRequest(
      NavigationRequestCallback callback) async {
    navigate = callback;
  }

  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback callback) async {}
}

class _Controller extends PlatformWebViewController {
  _Controller(super.params) : super.implementation();
  final scripts = <String>[];
  final loads = <Uri>[];
  bool login = false;
  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}
  @override
  Future<void> setPlatformNavigationDelegate(
      PlatformNavigationDelegate delegate) async {}
  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    loads.add(params.uri);
  }

  @override
  Future<Object> runJavaScriptReturningResult(String script) async {
    scripts.add(script);
    if (script.contains('HTMLFormElement.prototype.submit.call(form)')) {
      return true;
    }
    return jsonEncode({'login': login, 'document': login ? 'cas' : 'portal'});
  }
}

void main() {
  late _Camera camera;
  late MobileScannerPlatform original;
  setUp(() {
    original = MobileScannerPlatform.instance;
    camera = _Camera();
    MobileScannerPlatform.instance = camera;
  });
  tearDown(() async {
    MobileScannerPlatform.instance = original;
    await camera.captures.close();
  });

  Future<void> scanPage(WidgetTester tester, void Function(Uri?) done) async {
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async {
                      done(await Navigator.of(context).push<Uri>(
                          MaterialPageRoute(
                              builder: (_) => const AttendanceQrScreen())));
                    },
                    child: const Text('Skanuj'))))));
    await tester.tap(find.text('Skanuj'));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'scanner rejects unrelated QR then returns valid registration once',
      (tester) async {
    Uri? result;
    await scanPage(tester, (uri) => result = uri);
    camera.captures.add(const BarcodeCapture(
        barcodes: [Barcode(rawValue: 'https://evil.example')]));
    await tester.pumpAndSettle();
    expect(find.text('To nie jest kod rejestracji obecności UEK.'),
        findsOneWidget);
    camera.captures.add(const BarcodeCapture(
        barcodes: [Barcode(rawValue: _url), Barcode(rawValue: _url)]));
    await tester.pumpAndSettle();
    expect(result.toString(), _url);
    expect(find.byType(AttendanceQrScreen), findsNothing);
    expect(camera.stops, greaterThanOrEqualTo(1));
  });

  testWidgets('manual code remains available when camera permission is denied',
      (tester) async {
    camera.deny = true;
    Uri? result;
    await scanPage(tester, (uri) => result = uri);
    expect(find.text('Brak dostępu do aparatu'), findsOneWidget);
    expect(find.byType(Slider), findsNothing);
    await tester.tap(find.byTooltip('Wpisz kod rejestracji'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '123 456 789');
    await tester.tap(find.text('Otwórz'));
    await tester.pumpAndSettle();
    expect(result.toString(), _url);
    expect(tester.takeException(), isNull);
  });

  testWidgets('camera zoom controls adjust real scanner zoom within its limits',
      (tester) async {
    await scanPage(tester, (_) {});
    await tester.tap(find.byTooltip('Przybliż'));
    await tester.pumpAndSettle();
    expect(camera.zooms.last, closeTo(0.1, 0.001));
    tester.widget<Slider>(find.byType(Slider)).onChanged!(0.8);
    await tester.pumpAndSettle();
    expect(camera.zooms.last, closeTo(0.8, 0.001));
    await tester.tap(find.byTooltip('Oddal'));
    await tester.pumpAndSettle();
    expect(camera.zooms.last, closeTo(0.7, 0.001));
    expect(camera.zooms.every((value) => value >= 0 && value <= 1), isTrue);
    await tester.pageBack();
    await tester.pumpAndSettle();
  });

  testWidgets('registration logs into CAS but never submits attendance itself',
      (tester) async {
    final previous = WebViewPlatform.instance;
    final web = _Web();
    WebViewPlatform.instance = web;
    addTearDown(() {
      if (previous != null) WebViewPlatform.instance = previous;
    });
    await tester.pumpWidget(ProviderScope(
        overrides: [authServiceProvider.overrideWithValue(_Auth())],
        child: MaterialApp(
            home: AttendanceRegistrationScreen(url: Uri.parse(_url)))));
    await tester.pump();
    expect(web.controller.loads.single.toString(), _url);
    web.controller.login = true;
    web.delegate.finished('https://logowanie.uek.krakow.pl/cas/login');
    await tester.pumpAndSettle();
    web.controller.login = false;
    web.delegate.finished(_url);
    await tester.pumpAndSettle();
    final submissions = web.controller.scripts.where((script) =>
        script.contains('HTMLFormElement.prototype.submit.call(form)'));
    expect(submissions, hasLength(1));
    expect(submissions.single, contains("location"));
    expect(find.text('Strona rejestracji UEK'), findsOneWidget);
    expect(
        await web.delegate.navigate(const NavigationRequest(
            url: 'https://evil.example', isMainFrame: true)),
        NavigationDecision.prevent);
    expect(
        await web.delegate
            .navigate(const NavigationRequest(url: _url, isMainFrame: true)),
        NavigationDecision.navigate);
  });
}
