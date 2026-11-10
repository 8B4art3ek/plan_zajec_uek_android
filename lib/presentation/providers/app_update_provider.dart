import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/app_update_service.dart';

final appUpdateProvider = ChangeNotifierProvider<AppUpdateController>((ref) {
  return AppUpdateController(AppUpdateService(), AppUpdatePlatform());
});

class AppUpdateController extends ChangeNotifier {
  AppUpdateController(this._service, this._platform);
  final AppUpdateService _service;
  final AppUpdatePlatform _platform;
  InstalledApp? installed;
  AppRelease? release;
  File? _file;
  bool checking = false;
  bool downloading = false;
  bool installing = false;
  bool checked = false;
  bool permissionNeeded = false;
  bool _disposed = false;
  bool _cancelled = false;
  int received = 0;
  String? error;
  bool get busy => checking || downloading || installing;
  bool get available =>
      release != null && installed != null && release!.build > installed!.build;
  bool get ready => _file != null;

  Future<void> check() async {
    if (busy || _disposed) return;
    checking = true;
    error = null;
    permissionNeeded = false;
    _file = null;
    release = null;
    _notify();
    try {
      installed = await _platform.installedApp();
      release = await _service.latest(abi: installed!.abi);
      checked = true;
    } catch (e) {
      error = _message(e);
    } finally {
      checking = false;
      _notify();
    }
  }

  Future<void> download() async {
    if (busy || !available || _disposed) return;
    final update = release!;
    downloading = true;
    _cancelled = false;
    received = 0;
    error = null;
    permissionNeeded = false;
    _file = null;
    _notify();
    File? downloaded;
    try {
      final directory = await _platform.downloadDirectory();
      if (_cancelled || _disposed) throw UpdateCancelled();
      downloaded = await _service.download(update, directory, (value, total) {
        // Limit redraws while streaming a large APK.
        if (value == total || value - received >= 256 * 1024) {
          received = value;
          _notify();
        }
      });
      if (_cancelled || _disposed) throw UpdateCancelled();
      await _platform.verify(downloaded, update);
      if (_cancelled || _disposed) throw UpdateCancelled();
      _file = downloaded;
    } catch (e) {
      if (downloaded != null && await downloaded.exists()) {
        await downloaded.delete();
      }
      if (!_cancelled && e is! UpdateCancelled) error = _message(e);
    } finally {
      downloading = false;
      _notify();
    }
  }

  void cancel() {
    _cancelled = true;
    _service.cancelDownload();
  }

  Future<void> install() async {
    if (busy || _file == null || !available || _disposed) return;
    installing = true;
    error = null;
    _notify();
    try {
      permissionNeeded = !await _platform.install(_file!, release!);
    } catch (e) {
      error = _message(e);
    } finally {
      installing = false;
      _notify();
    }
  }

  String _message(Object e) {
    if (e is UpdateFailure) return e.message;
    if (e is FormatException) return e.message;
    if (e is PlatformException) {
      return e.message ?? 'Nie udało się uruchomić instalatora.';
    }
    if (e is MissingPluginException) {
      return 'Aktualizacje są dostępne w aplikacji na Androida.';
    }
    if (e is FileSystemException) {
      return 'Nie udało się zapisać instalatora. Sprawdź wolne miejsce w telefonie.';
    }
    if (e is TimeoutException) {
      return 'Serwer nie odpowiedział. Spróbuj ponownie.';
    }
    return 'Nie udało się połączyć z serwerem aktualizacji. Sprawdź internet i spróbuj ponownie.';
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _service.dispose();
    super.dispose();
  }
}
