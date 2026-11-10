import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

/// Exposes the visible Flutter list to Android's scrolling screenshot session.
class AppScrollView extends StatefulWidget {
  const AppScrollView({super.key, required this.child});
  final Widget child;

  @override
  State<AppScrollView> createState() => _AppScrollViewState();
}

class _AppScrollViewState extends State<AppScrollView> {
  static const _channel = MethodChannel('uek_plan/scroll_capture');
  static final _views = <_AppScrollViewState>[];
  static _AppScrollViewState? _session;
  final _controller = ScrollController();
  final _boundaryKey = GlobalKey();
  double _initialOffset = 0;
  int _captureGeneration = 0;

  @override
  void initState() {
    super.initState();
    _views.add(this);
    _channel.setMethodCallHandler(_handle);
  }

  static Future<Object?> _handle(MethodCall call) async {
    if (call.method == 'search') {
      _AppScrollViewState? selected;
      for (final view in _views.reversed) {
        if (view._isVisible) {
          selected = view;
          break;
        }
      }
      return selected?._bounds();
    }
    if (call.method == 'start') {
      for (final view in _views.reversed) {
        if (view._isVisible) {
          _session = view;
          view._captureGeneration++;
          view._initialOffset = view._controller.offset;
          view._controller.jumpTo(view._initialOffset);
          return true;
        }
      }
      return false;
    }
    if (call.method == 'end') {
      final session = _session;
      _session = null;
      if (session != null) session._captureGeneration++;
      if (session != null &&
          session.mounted &&
          session._controller.hasClients) {
        session._controller.jumpTo(session._initialOffset.clamp(
            session._controller.position.minScrollExtent,
            session._controller.position.maxScrollExtent));
        await _renderFrame();
      }
      return null;
    }
    if (call.method == 'capture') {
      return _session
          ?._capture(Map<String, dynamic>.from(call.arguments as Map));
    }
    throw MissingPluginException();
  }

  bool get _isVisible {
    if (!mounted ||
        !_controller.hasClients ||
        _controller.positions.length != 1 ||
        !_controller.position.hasContentDimensions ||
        _controller.position.maxScrollExtent <= 0 ||
        ModalRoute.of(context)?.isCurrent == false ||
        MediaQuery.viewInsetsOf(context).bottom > 0) {
      return false;
    }
    final box = _boundaryKey.currentContext?.findRenderObject();
    if (box is! RenderBox ||
        !box.attached ||
        !box.hasSize ||
        box.size.isEmpty) {
      return false;
    }
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(
        result,
        box.localToGlobal(box.size.center(Offset.zero)),
        View.of(context).viewId);
    return result.path.any((entry) => entry.target == box);
  }

  Map<String, double> _bounds() {
    final box = _boundaryKey.currentContext!.findRenderObject() as RenderBox;
    final origin = box.localToGlobal(Offset.zero);
    final ratio = MediaQuery.devicePixelRatioOf(context);
    return {
      'left': origin.dx * ratio,
      'top': origin.dy * ratio,
      'right': (origin.dx + box.size.width) * ratio,
      'bottom': (origin.dy + box.size.height) * ratio
    };
  }

  static Future<void> _renderFrame() async {
    final binding = WidgetsBinding.instance;
    final frame = binding.endOfFrame;
    // Screenshot overlays can pause normal frames while capture is still active.
    if (!binding.framesEnabled) {
      binding.scheduleWarmUpFrame();
    } else {
      binding.scheduleForcedFrame();
    }
    await frame.timeout(const Duration(milliseconds: 250), onTimeout: () async {
      binding.scheduleWarmUpFrame();
      await binding.endOfFrame.timeout(const Duration(milliseconds: 500));
    });
  }

  Future<Object?> _capture(Map<String, dynamic> request) async {
    if (!mounted || !_controller.hasClients) return null;
    final generation = ++_captureGeneration;
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final requested = Rect.fromLTRB(
        (request['left'] as num).toDouble(),
        (request['top'] as num).toDouble(),
        (request['right'] as num).toDouble(),
        (request['bottom'] as num).toDouble());
    final position = _controller.position;
    _controller.jumpTo((_initialOffset + requested.top / ratio)
        .clamp(position.minScrollExtent, position.maxScrollExtent));
    await _renderFrame();
    if (!mounted || _session != this || generation != _captureGeneration) {
      return null;
    }
    // Give lazily built slivers a second layout before reading the final offset.
    await _renderFrame();
    if (!mounted || _session != this || generation != _captureGeneration) {
      return null;
    }
    final boundary = _boundaryKey.currentContext!.findRenderObject()
        as RenderRepaintBoundary;
    final delta = ((_controller.offset - _initialOffset) * ratio).round();
    final width = (boundary.size.width * ratio).round();
    final height = (boundary.size.height * ratio).round();
    final area = requested.intersect(Rect.fromLTWH(
        0, delta.toDouble(), width.toDouble(), height.toDouble()));
    if (area.isEmpty) return null;
    final left = area.left.ceil();
    final top = area.top.ceil();
    final right = math.min(area.right.floor(), width);
    final bottom = area.bottom.floor();
    if (right <= left || bottom <= top) return null;
    final image = await boundary.toImage(pixelRatio: ratio);
    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImageRect(
          image,
          Rect.fromLTWH(left.toDouble(), (top - delta).toDouble(),
              (right - left).toDouble(), (bottom - top).toDouble()),
          Rect.fromLTWH(
              0, 0, (right - left).toDouble(), (bottom - top).toDouble()),
          Paint());
      final picture = recorder.endRecording();
      final cropped = await picture.toImage(right - left, bottom - top);
      picture.dispose();
      try {
        // Avoid PNG encoding/decoding inside Android's capture deadline.
        final bytes =
            await cropped.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (!mounted || _session != this || generation != _captureGeneration) {
          return null;
        }
        return {
          'left': left,
          'top': top,
          'right': right,
          'bottom': bottom,
          'rgba': bytes!.buffer.asUint8List(),
          'width': right - left,
          'height': bottom - top,
        };
      } finally {
        cropped.dispose();
      }
    } finally {
      image.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => PrimaryScrollController(
        controller: _controller,
        automaticallyInheritForPlatforms: TargetPlatform.values.toSet(),
        child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: RepaintBoundary(
                  key: _boundaryKey,
                  child: ColoredBox(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      child: widget.child)),
            )),
      );

  @override
  void dispose() {
    _views.remove(this);
    if (_session == this) _session = null;
    if (_views.isEmpty) _channel.setMethodCallHandler(null);
    _controller.dispose();
    super.dispose();
  }
}
