import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plan_zajec_uek/data/datasources/app_update_service.dart';
import 'package:plan_zajec_uek/presentation/providers/app_update_provider.dart';

final _bytes = utf8.encode('test APK');

Map<String, dynamic> _metadata() => {
      'tag_name': 'v1.0.1+2',
      'draft': false,
      'prerelease': false,
      'body': 'Nowe aktualizacje',
      'assets': <Map<String, dynamic>>[
        <String, dynamic>{
          'name': 'uek-plan.apk',
          'browser_download_url':
              'https://github.com/$updateRepository/releases/download/v1.0.1%2B2/uek-plan.apk',
          'size': _bytes.length,
          'digest': 'sha256:${crypto.sha256.convert(_bytes)}',
        }
      ],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final abi in ['arm64-v8a', 'armeabi-v7a', 'x86_64']) {
    test('prefers matching APK for $abi', () {
      final data = _metadata();
      final asset = Map<String, dynamic>.from(data['assets'][0]);
      asset['name'] = 'uek-plan-$abi.apk';
      asset['browser_download_url'] = (asset['browser_download_url'] as String)
          .replaceFirst('uek-plan.apk', asset['name'] as String);
      asset['size'] = 4;
      data['assets'].add(asset);
      final release = AppRelease.fromJson(data, abi: abi);
      expect(release.url.path, endsWith('uek-plan-$abi.apk'));
      expect(release.size, 4);
      expect(AppRelease.fromJson(data).url.path, endsWith('/uek-plan.apk'));
    });
  }

  test('falls back to universal when ABI variant is absent or unsupported', () {
    for (final abi in ['arm64-v8a', 'unknown', null]) {
      expect(AppRelease.fromJson(_metadata(), abi: abi).url.path,
          endsWith('/uek-plan.apk'));
    }
  });

  test('refuses a dedicated APK pointing at the universal download', () {
    final data = _metadata();
    final asset = Map<String, dynamic>.from(data['assets'][0]);
    asset['name'] = 'uek-plan-arm64-v8a.apk';
    data['assets'].add(asset);
    expect(() => AppRelease.fromJson(data, abi: 'arm64-v8a'),
        throwsFormatException);
  });

  test('reads release version, build, SHA256 and encoded tag', () {
    final release = AppRelease.fromJson(_metadata());
    expect(release.version, '1.0.1');
    expect(release.build, 2);
    expect(release.sha256, crypto.sha256.convert(_bytes).toString());
  });

  for (final change in <String, void Function(Map<String, dynamic>)>{
    'draft': (m) => m['draft'] = true,
    'prerelease': (m) => m['prerelease'] = true,
    'missing build': (m) => m['tag_name'] = 'v1.0.1',
    'missing hash': (m) => m['assets'][0]['digest'] = null,
    'invalid size': (m) => m['assets'][0]['size'] = -1,
    'foreign URL': (m) => m['assets'][0]['browser_download_url'] =
        'https://example.com/uek-plan.apk',
    'foreign repository': (m) => m['assets'][0]['browser_download_url'] =
        'https://github.com/other/repo/releases/download/v1.0.1+2/uek-plan.apk',
    'duplicate APK': (m) =>
        m['assets'].add(Map<String, dynamic>.from(m['assets'][0])),
  }.entries) {
    test('rejects ${change.key}', () {
      final data = _metadata();
      change.value(data);
      expect(() => AppRelease.fromJson(data), throwsFormatException);
    });
  }

  test('latest uses public API without credentials', () async {
    final service = AppUpdateService(
        clientFactory: () => MockClient((request) async {
              expect(request.url.toString(),
                  'https://api.github.com/repos/$updateRepository/releases/latest');
              expect(request.headers.containsKey('Authorization'), false);
              expect(request.followRedirects, false);
              return http.Response(jsonEncode(_metadata()), 200);
            }));
    addTearDown(service.dispose);
    expect((await service.latest())!.build, 2);
  });

  for (final code in [404, 403, 429, 500]) {
    test('handles HTTP $code', () async {
      final service = AppUpdateService(
          clientFactory: () =>
              MockClient((_) async => http.Response('', code)));
      addTearDown(service.dispose);
      if (code == 404) {
        expect(await service.latest(), isNull);
      } else {
        await expectLater(service.latest(), throwsA(isA<UpdateFailure>()));
      }
    });
  }

  group('download', () {
    late Directory directory;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('uek-update-test');
    });
    tearDown(() async {
      await directory.delete(recursive: true);
    });

    test('streams verified file and reports progress', () async {
      final service = AppUpdateService(
          clientFactory: () =>
              MockClient((_) async => http.Response.bytes(_bytes, 200)));
      addTearDown(service.dispose);
      var received = 0;
      final file = await service.download(AppRelease.fromJson(_metadata()),
          directory, (value, _) => received = value);
      expect(await file.readAsBytes(), _bytes);
      expect(received, _bytes.length);
      expect(await File('${directory.path}/update.part').exists(), false);
    });

    test('corrupt hash removes partial file', () async {
      final service = AppUpdateService(
          clientFactory: () => MockClient((_) async =>
              http.Response.bytes(List.filled(_bytes.length, 0), 200)));
      addTearDown(service.dispose);
      await expectLater(
          service.download(
              AppRelease.fromJson(_metadata()), directory, (_, __) {}),
          throwsA(isA<UpdateFailure>()));
      expect(await directory.list().toList(), isEmpty);
    });

    test('wrong content length removes partial file', () async {
      final service = AppUpdateService(
          clientFactory: () =>
              MockClient((_) async => http.Response('x', 200)));
      addTearDown(service.dispose);
      await expectLater(
          service.download(
              AppRelease.fromJson(_metadata()), directory, (_, __) {}),
          throwsA(isA<UpdateFailure>()));
      expect(await directory.list().toList(), isEmpty);
    });

    test('follows GitHub asset CDN redirect', () async {
      var requests = 0;
      final service = AppUpdateService(
          clientFactory: () => MockClient((request) async {
                requests++;
                if (requests == 1) {
                  return http.Response('', 302, headers: {
                    'location':
                        'https://release-assets.githubusercontent.com/test'
                  });
                }
                expect(
                    request.url.host, 'release-assets.githubusercontent.com');
                return http.Response.bytes(_bytes, 200);
              }));
      addTearDown(service.dispose);
      await service.download(
          AppRelease.fromJson(_metadata()), directory, (_, __) {});
      expect(requests, 2);
    });

    test('rejects redirect outside GitHub before requesting it', () async {
      var requests = 0;
      final service = AppUpdateService(
          clientFactory: () => MockClient((_) async {
                requests++;
                return http.Response('', 302,
                    headers: {'location': 'https://example.com/update.apk'});
              }));
      addTearDown(service.dispose);
      await expectLater(
          service.download(
              AppRelease.fromJson(_metadata()), directory, (_, __) {}),
          throwsA(isA<UpdateFailure>()));
      expect(requests, 1);
    });

    test('cancelled download cannot leave installable file', () async {
      final service = AppUpdateService(
          clientFactory: () =>
              MockClient((_) async => http.Response.bytes(_bytes, 200)));
      addTearDown(service.dispose);
      await expectLater(
          service.download(AppRelease.fromJson(_metadata()), directory,
              (_, __) => service.cancelDownload()),
          throwsA(isA<UpdateCancelled>()));
      expect(await directory.list().toList(), isEmpty);
      // A subsequent attempt remains possible.
      expect(
          await (await service.download(
                  AppRelease.fromJson(_metadata()), directory, (_, __) {}))
              .exists(),
          true);
    });

    test('controller verifies APK and retries install after permission',
        () async {
      final platform = _Platform(directory);
      final controller = AppUpdateController(_service(), platform);
      addTearDown(controller.dispose);
      await controller.check();
      expect(controller.available, true);
      await controller.download();
      expect(platform.verified, true);
      expect(controller.ready, true);
      await controller.install();
      expect(controller.permissionNeeded, true);
      platform.permission = true;
      await controller.install();
      expect(controller.permissionNeeded, false);
      expect(controller.error, isNull);
    });

    test('controller discards APK when signature check fails', () async {
      final platform = _Platform(directory)..rejectSignature = true;
      final controller = AppUpdateController(_service(), platform);
      addTearDown(controller.dispose);
      await controller.check();
      await controller.download();
      expect(controller.ready, false);
      expect(controller.error, 'Nieprawidłowy podpis.');
      expect(await directory.list().toList(), isEmpty);
    });

    test('equal and older builds are not offered', () async {
      for (final build in [2, 3]) {
        final controller = AppUpdateController(
            _service(), _Platform(directory)..build = build);
        await controller.check();
        expect(controller.available, false);
        await controller.download();
        expect(controller.ready, false);
        controller.dispose();
      }
    });

    test('simultaneous checks do not duplicate requests', () async {
      final response = Completer<http.Response>();
      var requests = 0;
      final service = AppUpdateService(
          clientFactory: () => MockClient((_) {
                requests++;
                return response.future;
              }));
      final controller = AppUpdateController(service, _Platform(directory));
      addTearDown(controller.dispose);
      final first = controller.check();
      await controller.check();
      response.complete(http.Response(jsonEncode(_metadata()), 200));
      await first;
      expect(requests, 1);
    });
  });
}

AppUpdateService _service() => AppUpdateService(
    clientFactory: () => MockClient((request) async =>
        request.url.host == 'api.github.com'
            ? http.Response(jsonEncode(_metadata()), 200)
            : http.Response.bytes(_bytes, 200)));

class _Platform extends AppUpdatePlatform {
  _Platform(this.directory);
  final Directory directory;
  bool verified = false;
  bool permission = false;
  bool rejectSignature = false;
  int build = 1;
  @override
  Future<InstalledApp> installedApp() async =>
      InstalledApp('1.0.0', build, 'com.example.plan_zajec_uek');
  @override
  Future<Directory> downloadDirectory() async => directory;
  @override
  Future<void> verify(File file, AppRelease release) async {
    if (rejectSignature) {
      throw PlatformException(
          code: 'INVALID_UPDATE', message: 'Nieprawidłowy podpis.');
    }
    verified = true;
  }

  @override
  Future<bool> install(File file, AppRelease release) async => permission;
}
