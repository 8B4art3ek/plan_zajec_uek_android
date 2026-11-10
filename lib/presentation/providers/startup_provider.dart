import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/datasources/app_update_service.dart';
import '../../data/datasources/startup_service.dart';
import 'providers.dart';

final startupServiceProvider = Provider((ref) => StartupService(
      ref.watch(scheduleRepositoryProvider),
      AppUpdatePlatform().installedApp,
    ));
