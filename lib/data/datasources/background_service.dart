// lib/data/datasources/background_service.dart

import 'package:workmanager/workmanager.dart';
import '../../core/refresh_settings.dart';
import 'local_database.dart';
import 'notification_service.dart';
import 'schedule_parser.dart';
import 'schedule_remote_datasource.dart';
import 'auth_service.dart';
import '../repositories/schedule_repository_impl.dart';

const _refreshTaskName = 'schedule_refresh';
const _refreshTaskId = 'uek_schedule_refresh';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == _refreshTaskName) {
      final db = LocalDatabase();
      final remote = ScheduleRemoteDatasource();
      try {
        final auth = AuthService();
        if (await auth.getCredentials() == null) return true;
        final minutes =
            RefreshSettings.parse(await db.getSetting(RefreshSettings.key));
        if (minutes == 0) return true;
        final parser = ScheduleParser();
        final repo = ScheduleRepository(
          db: db,
          remote: remote,
          parser: parser,
          auth: auth,
        );

        final nextAttempt = await repo.automaticRefreshDueAt();
        if (nextAttempt != null && DateTime.now().isBefore(nextAttempt)) {
          return true;
        }
        final result = await repo.refreshAllGroups();
        if (result.changes.isNotEmpty) {
          final notif = NotificationService();
          await notif.init();
          await notif.showScheduleChangedNotification(result.changes);
        }
        return result.isSuccessful;
      } catch (e) {
        return false;
      } finally {
        remote.close();
        await db.close();
      }
    }
    return false;
  });
}

class BackgroundService {
  static Future<void> init() async {
    await Workmanager().initialize(callbackDispatcher);
  }

  static Future<void> schedulePeriodicRefresh({int? minutes}) async {
    if (minutes == null) {
      final db = LocalDatabase();
      try {
        minutes =
            RefreshSettings.parse(await db.getSetting(RefreshSettings.key));
      } finally {
        await db.close();
      }
    }
    if (!RefreshSettings.options.contains(minutes)) {
      throw ArgumentError.value(minutes);
    }
    if (minutes == 0) {
      await Workmanager().cancelByUniqueName(_refreshTaskId);
      return;
    }
    await Workmanager().registerPeriodicTask(
      _refreshTaskId,
      _refreshTaskName,
      frequency: Duration(minutes: minutes),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );
  }
}
