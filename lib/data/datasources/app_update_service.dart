import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

const updateRepository = '8B4art3ek/uek-plan-releases';

class InstalledApp {
  const InstalledApp(this.version, this.build, this.packageName, {this.abi});
  final String version;
  final int build;
  final String packageName;
  final String? abi;
}

class AppRelease {
  const AppRelease(
      {required this.version,
      required this.build,
      required this.notes,
      required this.url,
      required this.size,
      required this.sha256});
  final String version;
  final int build;
  final String notes;
  final Uri url;
  final int size;
  final String sha256;

  static AppRelease fromJson(Map<String, dynamic> json, {String? abi}) {
    final tag = json['tag_name'];
    final match = tag is String
        ? RegExp(r'^v(\d+\.\d+\.\d+)\+([1-9]\d*)$').firstMatch(tag)
        : null;
    if (match == null ||
        json['draft'] != false ||
        json['prerelease'] != false) {
      throw const FormatException(
          'Nieprawidłowe oznaczenie wersji aktualizacji.');
    }
    final assets = json['assets'];
    if (assets is! List) {
      throw const FormatException('Brak instalatora aktualizacji.');
    }
    var assetName = 'uek-plan.apk';
    if (const {'arm64-v8a', 'armeabi-v7a', 'x86_64'}.contains(abi)) {
      final specificName = 'uek-plan-$abi.apk';
      if (assets.whereType<Map>().any((a) => a['name'] == specificName)) {
        assetName = specificName;
      }
    }
    final apks =
        assets.whereType<Map>().where((a) => a['name'] == assetName).toList();
    if (apks.length != 1) {
      throw const FormatException(
          'Brak jednoznacznego instalatora aktualizacji.');
    }
    final asset = apks.single;
    final url = Uri.tryParse(asset['browser_download_url']?.toString() ?? '');
    final expectedPath = '/$updateRepository/releases/download/$tag/$assetName';
    if (url == null ||
        url.scheme != 'https' ||
        url.host != 'github.com' ||
        url.port != 443 ||
        url.userInfo.isNotEmpty ||
        url.hasQuery ||
        url.hasFragment ||
        Uri.decodeComponent(url.path) != expectedPath) {
      throw const FormatException(
          'Instalator nie pochodzi z repozytorium aplikacji.');
    }
    final size = asset['size'];
    final digest = asset['digest'];
    if (size is! int ||
        size <= 0 ||
        size > 2147483648 ||
        digest is! String ||
        !RegExp(r'^sha256:[a-fA-F0-9]{64}$').hasMatch(digest)) {
      throw const FormatException(
          'Brak poprawnego rozmiaru lub sumy kontrolnej aktualizacji.');
    }
    return AppRelease(
        version: match.group(1)!,
        build: int.parse(match.group(2)!),
        notes: json['body'] is String ? json['body'] as String : '',
        url: url,
        size: size,
        sha256: digest.substring(7).toLowerCase());
  }
}

class UpdateFailure implements Exception {
  const UpdateFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class UpdateCancelled implements Exception {}

class AppUpdatePlatform {
  static const _channel = MethodChannel('uek_plan/app_updates');

  Future<InstalledApp> installedApp() async {
    final info =
        await _channel.invokeMapMethod<String, dynamic>('installedApp');
    return InstalledApp(info!['version'] as String, info['build'] as int,
        info['packageName'] as String,
        abi: info['abi'] as String?);
  }

  Future<Directory> downloadDirectory() async =>
      Directory((await _channel.invokeMethod<String>('downloadDirectory'))!);

  Future<void> verify(File file, AppRelease release) async {
    await _channel.invokeMethod<void>('verifyUpdate', {
      'path': file.path,
      'build': release.build,
      'version': release.version,
    });
  }

  Future<bool> install(File file, AppRelease release) async =>
      await _channel.invokeMethod<bool>('installUpdate', {
        'path': file.path,
        'build': release.build,
        'version': release.version,
      }) ??
      false;
}

class AppUpdateService {
  AppUpdateService({http.Client Function()? clientFactory})
      : _clientFactory = clientFactory ?? http.Client.new;
  final http.Client Function() _clientFactory;
  http.Client? _downloadClient;
  final _metadataClients = <http.Client>{};
  bool _cancelled = false;
  bool _disposed = false;

  Future<AppRelease?> latest({String? abi}) async {
    if (_disposed) throw UpdateCancelled();
    final client = _clientFactory();
    _metadataClients.add(client);
    try {
      final request = http.Request(
          'GET',
          Uri.https(
              'api.github.com', '/repos/$updateRepository/releases/latest'))
        ..followRedirects = false
        ..headers.addAll({
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'UEK-Plan-Updates'
        });
      final response =
          await client.send(request).timeout(const Duration(seconds: 20));
      if (response.statusCode == 404) return null;
      if (response.statusCode == 403 || response.statusCode == 429) {
        throw const UpdateFailure(
            'GitHub chwilowo ogranicza zapytania. Spróbuj później.');
      }
      if (response.statusCode != 200) {
        throw UpdateFailure(
            'Nie udało się sprawdzić aktualizacji (HTTP ${response.statusCode}).');
      }
      final bytes = <int>[];
      await for (final chunk
          in response.stream.timeout(const Duration(seconds: 20))) {
        bytes.addAll(chunk);
        if (bytes.length > 1024 * 1024) {
          throw const UpdateFailure(
              'Odpowiedź serwera aktualizacji jest zbyt duża.');
        }
      }
      final data = jsonDecode(utf8.decode(bytes));
      if (data is! Map<String, dynamic>) {
        throw const FormatException(
            'Nieprawidłowa odpowiedź serwera aktualizacji.');
      }
      return AppRelease.fromJson(data, abi: abi);
    } finally {
      _metadataClients.remove(client);
      client.close();
    }
  }

  Future<File> download(AppRelease release, Directory directory,
      void Function(int received, int total) onProgress) async {
    if (_disposed) throw UpdateCancelled();
    if (_downloadClient != null) {
      throw const UpdateFailure('Pobieranie już trwa.');
    }
    _cancelled = false;
    final client = _clientFactory();
    _downloadClient = client;
    final partial = File('${directory.path}/update.part');
    final target = File('${directory.path}/update.apk');
    RandomAccessFile? output;
    try {
      await directory.create(recursive: true);
      if (await target.exists()) await target.delete();
      var uri = release.url;
      http.StreamedResponse? response;
      for (var redirects = 0; redirects <= 5; redirects++) {
        _checkCancelled();
        if (uri.scheme != 'https' ||
            uri.port != 443 ||
            uri.userInfo.isNotEmpty ||
            !const {
              'github.com',
              'release-assets.githubusercontent.com',
              'objects.githubusercontent.com'
            }.contains(uri.host)) {
          throw const UpdateFailure('Niebezpieczne przekierowanie pobierania.');
        }
        final request = http.Request('GET', uri)..followRedirects = false;
        response =
            await client.send(request).timeout(const Duration(seconds: 30));
        if (!const {301, 302, 303, 307, 308}.contains(response.statusCode)) {
          break;
        }
        final location = response.headers['location'];
        await response.stream.listen(null).cancel();
        if (location == null || redirects == 5) {
          throw const UpdateFailure('Nie udało się odnaleźć instalatora.');
        }
        uri = uri.resolve(location);
      }
      if (response == null || response.statusCode != 200) {
        throw const UpdateFailure('Nie udało się pobrać instalatora.');
      }
      if (response.contentLength != null &&
          response.contentLength != release.size) {
        throw const UpdateFailure(
            'Rozmiar instalatora nie zgadza się z wydaniem.');
      }
      final digest = _DigestSink();
      final hasher = sha256.startChunkedConversion(digest);
      output = await partial.open(mode: FileMode.write);
      var received = 0;
      await for (final chunk
          in response.stream.timeout(const Duration(seconds: 30))) {
        _checkCancelled();
        received += chunk.length;
        if (received > release.size) {
          throw const UpdateFailure('Instalator jest większy niż oczekiwano.');
        }
        hasher.add(chunk);
        await output.writeFrom(chunk);
        onProgress(received, release.size);
      }
      hasher.close();
      _checkCancelled();
      if (received != release.size ||
          digest.value?.toString() != release.sha256) {
        throw const UpdateFailure(
            'Plik jest niekompletny lub uszkodzony. Pobierz aktualizację ponownie.');
      }
      await output.close();
      output = null;
      return await partial.rename(target.path);
    } catch (_) {
      if (_cancelled || _disposed) throw UpdateCancelled();
      rethrow;
    } finally {
      try {
        await output?.close();
        if (await partial.exists()) await partial.delete();
      } finally {
        client.close();
        _downloadClient = null;
      }
    }
  }

  void _checkCancelled() {
    if (_cancelled || _disposed) throw UpdateCancelled();
  }

  void cancelDownload() {
    _cancelled = true;
    _downloadClient?.close();
  }

  void dispose() {
    _disposed = true;
    cancelDownload();
    for (final client in _metadataClients) {
      client.close();
    }
    _metadataClients.clear();
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
