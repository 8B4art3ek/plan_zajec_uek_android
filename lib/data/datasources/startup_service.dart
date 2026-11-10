import '../../core/release_notes.dart';
import '../repositories/schedule_repository_impl.dart';
import 'app_update_service.dart';

class StartupRelease {
  const StartupRelease(this.installed, this.notes);
  final InstalledApp installed;
  final List<String> notes;
}

class StartupService {
  const StartupService(this.repository, this.readInstalled);
  final ScheduleRepository repository;
  final Future<InstalledApp> Function() readInstalled;
  static const seenBuildKey = 'last_seen_release_build';

  Future<StartupRelease?> pendingRelease() async {
    final installed = await readInstalled();
    final seen =
        int.tryParse(await repository.getAppSetting(seenBuildKey) ?? '');
    if (seen != null && seen >= installed.build) return null;
    final notes = [
      for (final release in releaseNotesByBuild.entries)
        if (release.key <= installed.build &&
            (seen == null
                ? release.key == installed.build
                : release.key > seen))
          ...release.value,
    ];
    if (notes.isEmpty) return null;
    return StartupRelease(installed, notes);
  }

  Future<void> acknowledgeRelease(StartupRelease release) =>
      repository.setAppSetting(seenBuildKey, '${release.installed.build}');
}
