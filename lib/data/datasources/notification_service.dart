// lib/data/datasources/notification_service.dart

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../../domain/entities/schedule_change.dart';
import '../../domain/entities/schedule_notification.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    const androidSettings = AndroidInitializationSettings('ic_stat_schedule');
    const initSettings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(initSettings);
  }

  Future<void> showScheduleChangedNotification(
      List<ScheduleChange> changes) async {
    final content = ScheduleNotification.fromChanges(changes);
    if (content == null) return;
    final androidDetails = AndroidNotificationDetails(
      'schedule_changes',
      'Zmiany w planie',
      channelDescription: 'Powiadomienia o zmianach w planie zajęć',
      importance: Importance.high,
      priority: Priority.high,
      icon: 'ic_stat_schedule',
      visibility: NotificationVisibility.private,
      styleInformation: BigTextStyleInformation(content.details),
    );
    final details = NotificationDetails(android: androidDetails);
    await _plugin.show(
      1001,
      content.title,
      content.body,
      details,
      payload: 'schedule_changes',
    );
  }

  Future<void> requestPermission() async {
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }
}
