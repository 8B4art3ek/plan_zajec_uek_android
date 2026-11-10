import 'package:flutter_test/flutter_test.dart';
import 'package:plan_zajec_uek/data/datasources/app_update_service.dart';
import 'package:plan_zajec_uek/data/datasources/auth_service.dart';
import 'package:plan_zajec_uek/data/datasources/local_database.dart';
import 'package:plan_zajec_uek/data/datasources/schedule_parser.dart';
import 'package:plan_zajec_uek/data/datasources/schedule_remote_datasource.dart';
import 'package:plan_zajec_uek/data/datasources/startup_service.dart';
import 'package:plan_zajec_uek/data/repositories/schedule_repository_impl.dart';

class _Settings extends LocalDatabase {
  final values = <String, String>{};
  @override
  Future<String?> getSetting(String key) async => values[key];
  @override
  Future<void> setSetting(String key, String value) async {
    values[key] = value;
  }
}

void main() {
  late _Settings db;
  late ScheduleRemoteDatasource remote;
  late StartupService service;
  setUp(() {
    db = _Settings();
    remote = ScheduleRemoteDatasource();
    final repo = ScheduleRepository(
        db: db, remote: remote, parser: ScheduleParser(), auth: AuthService());
    service = StartupService(
        repo, () async => const InstalledApp('1.0.5', 6, 'test'));
  });
  tearDown(() => remote.close());
  test(
      'release news stays pending until explicitly acknowledged and then disappears',
      () async {
    final release = await service.pendingRelease();
    expect(
        release!.notes,
        contains(
            'Po zalogowaniu wybierzesz import grup z USOS lub ręczne dodawanie po ID.'));
    expect(await service.pendingRelease(), isNotNull);
    await service.acknowledgeRelease(release);
    expect(db.values[StartupService.seenBuildKey], '6');
    expect(await service.pendingRelease(), isNull);
  });
  test('skipped updates include their news, but never future releases',
      () async {
    db.values[StartupService.seenBuildKey] = '4';
    final release = await service.pendingRelease();
    expect(release!.notes, contains('Podział obecności na semestry.'));
    expect(release.notes.any((note) => note.contains('ręczne')), isTrue);
    db.values[StartupService.seenBuildKey] = '7';
    expect(await service.pendingRelease(), isNull);
  });
}
