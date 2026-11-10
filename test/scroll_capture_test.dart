import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plan_zajec_uek/presentation/widgets/app_scroll_view.dart';

Future<Object?> _call(WidgetTester tester, String method, [Object? args]) {
  const codec = StandardMethodCodec();
  final completer = Completer<Object?>();
  tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'uek_plan/scroll_capture',
    codec.encodeMethodCall(MethodCall(method, args)),
    (ByteData? data) =>
        completer.complete(data == null ? null : codec.decodeEnvelope(data)),
  );
  return completer.future;
}

Widget _list(String prefix) => AppScrollView(
        child: ListView.builder(
      itemExtent: 100,
      itemCount: 30,
      itemBuilder: (_, index) => ColoredBox(
          color: index.isEven ? Colors.red : Colors.blue,
          child: Text('$prefix $index')),
    ));

void main() {
  testWidgets('captures while the screenshot overlay has paused normal frames',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(800, 600);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: _list('Paused'))));
    await tester.pumpAndSettle();
    final position =
        tester.state<ScrollableState>(find.byType(Scrollable)).position;
    position.jumpTo(150);
    await tester.pumpAndSettle();
    expect(await _call(tester, 'start'), true);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    addTearDown(() => tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed));
    expect(tester.binding.framesEnabled, isFalse);
    // Do not pump: this must render without the normal Android vsync/frame path.
    final data = await tester.runAsync(() => _call(tester, 'capture', {
          'left': 0,
          'top': 500,
          'right': 800,
          'bottom': 800
        }).timeout(const Duration(seconds: 3))) as Map;
    expect(data['height'], 300);
    expect((data['rgba'] as Uint8List).take(4), [244, 67, 54, 255]);
    await tester.runAsync(
        () => _call(tester, 'end').timeout(const Duration(seconds: 3)));
    expect(position.pixels, 150);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
  });

  testWidgets(
      'high-DPI capture excludes bars and supports content above initial offset',
      (tester) async {
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(1080, 1920);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            appBar: AppBar(title: const Text('Plan dnia')),
            bottomNavigationBar: const SizedBox(height: 80),
            body: _list('DPI'))));
    await tester.pumpAndSettle();
    final bounds = await _call(tester, 'search') as Map;
    expect(bounds['top'], greaterThan(0));
    expect(bounds['right'], 1080);
    expect(bounds['bottom'], lessThan(1920));
    final position =
        tester.state<ScrollableState>(find.byType(Scrollable)).position;
    position.jumpTo(100);
    await tester.pumpAndSettle();
    await _call(tester, 'start');
    final data = await tester.runAsync(() async {
      final result = _call(tester, 'capture',
          {'left': 0, 'top': -150, 'right': 1080, 'bottom': 300});
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      return result.timeout(const Duration(seconds: 3));
    }) as Map;
    expect(data['top'], -150);
    expect(data['width'], 1080);
    expect(data['height'], 450);
    expect((data['rgba'] as Uint8List).length, 1080 * 450 * 4);
    final end = _call(tester, 'end');
    await tester.pump();
    await end;
    expect(position.pixels, 100);
  });

  testWidgets('ending a session cancels an in-flight tile and restores offset',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: _list('Cancel'))));
    await tester.pumpAndSettle();
    final position =
        tester.state<ScrollableState>(find.byType(Scrollable)).position;
    position.jumpTo(50);
    await tester.pumpAndSettle();
    await _call(tester, 'start');
    final capture = _call(tester, 'capture',
        {'left': 0, 'top': 300, 'right': 300, 'bottom': 600});
    final end = _call(tester, 'end');
    await tester.pump();
    await tester.pump();
    expect(await capture, isNull);
    await end;
    expect(position.pixels, 50);
  });

  testWidgets(
      'captures visible list, clamps at boundaries and restores scroll position',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(800, 600);
    addTearDown(tester.view.resetPhysicalSize);
    await tester
        .pumpWidget(MaterialApp(home: Scaffold(body: _list('Visible'))));
    await tester.pumpAndSettle();
    final bounds = await _call(tester, 'search') as Map;
    expect(bounds['right'], 800);
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    scrollable.position.jumpTo(150);
    await tester.pumpAndSettle();
    expect(await _call(tester, 'start'), true);
    final data = await tester.runAsync(() async {
      final result = _call(tester, 'capture',
          {'left': 0, 'top': 500, 'right': 800, 'bottom': 800});
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      return await result.timeout(const Duration(seconds: 5));
    }) as Map;
    expect(data['top'], 500);
    expect(data['bottom'], 800);
    expect(data['rgba'], isA<Uint8List>());
    expect(data['width'], 800);
    expect(data['height'], 300);
    expect((data['rgba'] as Uint8List).length, 800 * 300 * 4);
    expect((data['rgba'] as Uint8List).take(4), [244, 67, 54, 255]);
    expect(scrollable.position.pixels, 650);
    final outside = _call(tester, 'capture',
        {'left': 0, 'top': 6000, 'right': 800, 'bottom': 6300});
    await tester.pump();
    await tester.pump();
    expect(await outside, isNull);
    final end = _call(tester, 'end');
    await tester.pump();
    await end;
    expect(scrollable.position.pixels, 150);
  });

  testWidgets('ignores hidden tab and excludes modal routes and short content',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(800, 600);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: IndexedStack(
      index: 0,
      children: [_list('Visible'), _list('Hidden')],
    ))));
    await tester.pumpAndSettle();
    expect(await _call(tester, 'start'), true);
    final positions = tester
        .stateList<ScrollableState>(
            find.byType(Scrollable, skipOffstage: false))
        .toList();
    await tester.runAsync(() async {
      final capture = _call(tester, 'capture',
          {'left': 0, 'top': 400, 'right': 800, 'bottom': 500});
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      return await capture.timeout(const Duration(seconds: 5));
    });
    expect(positions[0].position.pixels, 400);
    expect(positions[1].position.pixels, 0);
    final end = _call(tester, 'end');
    await tester.pump();
    await end;
    final context = tester.element(find.byType(Scaffold));
    unawaited(showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(content: Text('Modal'))));
    await tester.pumpAndSettle();
    expect(await _call(tester, 'search'), isNull);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AppScrollView(
                child: ListView(children: const [Text('Short')])))));
    await tester.pumpAndSettle();
    expect(await _call(tester, 'search'), isNull);
  });
}
