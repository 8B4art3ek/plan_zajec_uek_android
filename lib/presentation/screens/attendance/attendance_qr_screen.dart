import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../../domain/entities/attendance_link.dart';
import '../../../data/datasources/uek_login_script.dart';
import '../../providers/providers.dart';
import '../../widgets/failure_view.dart';

class AttendanceQrScreen extends StatefulWidget {
  const AttendanceQrScreen({super.key});
  @override
  State<AttendanceQrScreen> createState() => _AttendanceQrScreenState();
}

class _AttendanceQrScreenState extends State<AttendanceQrScreen> {
  final _camera = MobileScannerController(
      formats: [BarcodeFormat.qrCode],
      detectionSpeed: DetectionSpeed.noDuplicates);
  bool _handled = false;
  String? _lastRejected;
  double _zoom = 0;
  double _gestureZoom = 0;
  bool _zoomBusy = false;

  Future<void> _setZoom(double value) async {
    if (!_camera.value.isRunning || _handled) return;
    setState(() => _zoom = value.clamp(0.0, 1.0));
    if (_zoomBusy) return;
    _zoomBusy = true;
    try {
      double applied;
      do {
        applied = _zoom;
        await _camera.setZoomScale(applied);
      } while (mounted && !_handled && applied != _zoom);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Przybliżanie jest niedostępne dla tego aparatu.')));
      }
    } finally {
      _zoomBusy = false;
    }
  }

  @override
  void dispose() {
    unawaited(_camera.dispose());
    super.dispose();
  }

  Future<void> _accept(String value) async {
    if (_handled) return;
    final uri = parseAttendanceLink(value);
    if (uri == null) {
      if (_lastRejected == value) return;
      _lastRejected = value;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('To nie jest kod rejestracji obecności UEK.')));
      return;
    }
    _handled = true;
    try {
      await _camera.stop();
    } catch (_) {/* The camera may already be stopped. */}
    if (mounted) Navigator.of(context).pop(uri);
  }

  Future<void> _manual() async {
    final value = await showDialog<String>(
        context: context, builder: (_) => const _AttendanceCodeDialog());
    if (value != null && mounted) await _accept(value);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: const Text('Skanuj obecność',
                maxLines: 1, overflow: TextOverflow.ellipsis),
            actions: [
              IconButton(
                  tooltip: 'Wpisz kod rejestracji',
                  icon: const Icon(Icons.keyboard_outlined),
                  onPressed: _manual),
              IconButton(
                  tooltip: 'Latarka',
                  icon: const Icon(Icons.flashlight_on_outlined),
                  onPressed: () async {
                    try {
                      await _camera.toggleTorch();
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Latarka jest niedostępna.')));
                      }
                    }
                  }),
            ]),
        body: Stack(children: [
          Positioned.fill(
              child: GestureDetector(
                  onScaleStart: (_) => _gestureZoom = _zoom,
                  onScaleUpdate: (details) {
                    if (details.pointerCount >= 2) {
                      unawaited(
                          _setZoom(_gestureZoom + (details.scale - 1) * 0.3));
                    }
                  },
                  child: MobileScanner(
                    controller: _camera,
                    onDetect: (capture) {
                      for (final barcode in capture.barcodes) {
                        final value = barcode.rawValue;
                        if (value != null) unawaited(_accept(value));
                      }
                    },
                    errorBuilder: (context, error) => Center(
                        child: SingleChildScrollView(
                            child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.no_photography_outlined,
                                          size: 40),
                                      const SizedBox(height: 16),
                                      Text(
                                          error.errorCode ==
                                                  MobileScannerErrorCode
                                                      .permissionDenied
                                              ? 'Brak dostępu do aparatu'
                                              : 'Nie można uruchomić aparatu',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium),
                                      const SizedBox(height: 8),
                                      const Text(
                                          'Dostęp do aparatu możesz włączyć w ustawieniach uprawnień aplikacji.',
                                          textAlign: TextAlign.center),
                                      TextButton.icon(
                                          onPressed: _manual,
                                          icon: const Icon(
                                              Icons.keyboard_outlined),
                                          label: const Text(
                                              'Wpisz kod rejestracji')),
                                    ])))),
                  ))),
          Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: SafeArea(
                  top: false,
                  child: ValueListenableBuilder(
                    valueListenable: _camera,
                    builder: (context, state, _) => !state.isRunning ||
                            state.error != null
                        ? const SizedBox.shrink()
                        : Material(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(8),
                            child: Row(children: [
                              IconButton(
                                  tooltip: 'Oddal',
                                  onPressed: _zoom > 0
                                      ? () => unawaited(_setZoom(_zoom - 0.1))
                                      : null,
                                  icon: const Icon(Icons.zoom_out,
                                      color: Colors.white)),
                              Expanded(
                                  child: Slider(
                                      value: _zoom,
                                      semanticFormatterCallback: (value) =>
                                          'Przybliżenie ${(value * 100).round()} procent',
                                      onChanged: (value) =>
                                          unawaited(_setZoom(value)))),
                              IconButton(
                                  tooltip: 'Przybliż',
                                  onPressed: _zoom < 1
                                      ? () => unawaited(_setZoom(_zoom + 0.1))
                                      : null,
                                  icon: const Icon(Icons.zoom_in,
                                      color: Colors.white)),
                            ])),
                  ))),
        ]),
      );
}

class _AttendanceCodeDialog extends StatefulWidget {
  const _AttendanceCodeDialog();
  @override
  State<_AttendanceCodeDialog> createState() => _AttendanceCodeDialogState();
}

class _AttendanceCodeDialogState extends State<_AttendanceCodeDialog> {
  final _text = TextEditingController();
  final _form = GlobalKey<FormState>();
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        scrollable: true,
        title: const Text('Kod rejestracji'),
        content: Form(
            key: _form,
            child: TextFormField(
                controller: _text,
                autofocus: true,
                autocorrect: false,
                decoration:
                    const InputDecoration(labelText: 'Kod lub adres QR'),
                validator: (value) => parseAttendanceLink(value ?? '') == null
                    ? 'Wpisz prawidłowy kod lub adres obecności UEK.'
                    : null)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Anuluj')),
          FilledButton(
              onPressed: () {
                if (_form.currentState!.validate()) {
                  Navigator.pop(context, _text.text);
                }
              },
              child: const Text('Otwórz'))
        ],
      );
}

class AttendanceRegistrationScreen extends ConsumerStatefulWidget {
  const AttendanceRegistrationScreen({super.key, required this.url});
  final Uri url;
  @override
  ConsumerState<AttendanceRegistrationScreen> createState() =>
      _AttendanceRegistrationScreenState();
}

class _AttendanceRegistrationScreenState
    extends ConsumerState<AttendanceRegistrationScreen> {
  late final WebViewController _web;
  final _submitted = <String>{};
  Object? _error;
  bool _loading = true;
  bool _handling = false;

  @override
  void initState() {
    super.initState();
    _web = WebViewController();
    unawaited(_configure());
  }

  Future<void> _configure() async {
    if (mounted) {
      setState(() {
        _error = null;
        _loading = true;
      });
    }
    try {
      await _web.setJavaScriptMode(JavaScriptMode.unrestricted);
      await _web.setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (request) {
          final uri = Uri.tryParse(request.url);
          return uri != null && isAttendanceNavigation(uri)
              ? NavigationDecision.navigate
              : NavigationDecision.prevent;
        },
        onPageStarted: (_) {
          if (mounted) {
            setState(() {
              _loading = true;
              _error = null;
            });
          }
        },
        onPageFinished: (_) => unawaited(_loaded()),
        onWebResourceError: (error) {
          if (mounted && error.isForMainFrame == true && _loading) {
            setState(() {
              _error = error.description;
              _loading = false;
            });
          }
        },
      ));
      if (!isAttendanceNavigation(widget.url)) {
        throw const FormatException('Nieprawidłowy adres obecności.');
      }
      await _web.loadRequest(widget.url);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    }
  }

  Future<void> _loaded() async {
    if (!mounted || _handling) return;
    _handling = true;
    try {
      final raw = await _web.runJavaScriptReturningResult(r'''
        JSON.stringify({login: location.hostname === 'logowanie.uek.krakow.pl' &&
          Boolean(document.querySelector('input[type="password"]')),
          document: String(performance.timeOrigin)})
      ''');
      Object? data = raw;
      if (data is String) data = jsonDecode(data);
      if (data is String) data = jsonDecode(data);
      if (data is Map && data['login'] == true) {
        final document = data['document'].toString();
        if (_submitted.add(document)) {
          if (_submitted.length == 1) {
            final credentials =
                await ref.read(authServiceProvider).getCredentials();
            if (credentials != null) {
              await _web.runJavaScriptReturningResult(
                  buildUekLoginScript(credentials));
            }
          } else if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Dokończ logowanie na stronie UEK.')));
          }
        }
      }
      // The registration page stays visible. Only the user confirms attendance.
      if (mounted) setState(() => _loading = false);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    } finally {
      _handling = false;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: const Text('Potwierdź obecność',
                maxLines: 1, overflow: TextOverflow.ellipsis),
            actions: [
              IconButton(
                  tooltip: 'Odśwież stronę',
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: () {
                    _submitted.clear();
                    unawaited(_configure());
                  }),
            ]),
        body: SafeArea(
            child: Stack(children: [
          WebViewWidget(controller: _web),
          if (_loading)
            const Align(
                alignment: Alignment.topCenter,
                child: LinearProgressIndicator()),
          if (_error != null)
            ColoredBox(
                color: Theme.of(context).colorScheme.surface,
                child: FailureView(
                    error: _error!,
                    onRetry: () {
                      _submitted.clear();
                      unawaited(_configure());
                    })),
        ])),
      );
}
