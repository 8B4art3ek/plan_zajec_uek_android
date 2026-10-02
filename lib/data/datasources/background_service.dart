// lib/data/datasources/background_service.dart

import 'package:workmanager/workmanager.dart';
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
      try {
        final db = LocalDatabase();
        final auth = AuthService();
        final remote = ScheduleRemoteDatasource();
        final parser = ScheduleParser();
        final repo = ScheduleRepository(
          db: db,
          remote: remote,
          parser: parser,
          auth: auth,
        );

        final changed = await repo.refreshAllGroups();
        if (changed) {
          final notif = NotificationService();
          await notif.init();
          await notif.showScheduleChangedNotification();
        }
        await db.close();
        return true;
      } catch (e) {
        return false;
      }
    }
    return false;
  });
}

class BackgroundService {
  static Future<void> init() async {
    await Workmanager().initialize(callbackDispatcher);
  }

  static Future<void> schedulePeriodicRefresh() async {
    await Workmanager().registerPeriodicTask(
      _refreshTaskId,
      _refreshTaskName,
      frequency: const Duration(hours: 1),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );
  }

  static Future<void> cancelAll() async {
    await Workmanager().cancelAll();
  }
}
