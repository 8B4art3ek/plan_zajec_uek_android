import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:plan_zajec_uek/data/datasources/notification_service.dart';
import 'package:plan_zajec_uek/domain/entities/schedule_change.dart';
import 'package:plan_zajec_uek/domain/entities/schedule_notification.dart';

ScheduleChange change(String subject, String description) => ScheduleChange(
    groupId: '1',
    subject: subject,
    description: description,
    detectedAt: DateTime(2026, 10, 20));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('single change includes subject, before/after date, time and room', () {
    final content = ScheduleNotification.fromChanges([
      change('Matematyka',
          'Zmieniono zajęcia\nPrzed: 21.10.2026 09:00–10:30 · sala A\nTeraz: 21.10.2026 12:00–13:30 · sala B')
    ])!;
    expect(content.title, 'Zmieniono zajęcia: Matematyka');
    expect(content.body, contains('→'));
    expect(content.details, contains('09:00–10:30'));
    expect(content.details, contains('12:00–13:30'));
    expect(content.details, contains('sala A'));
    expect(content.details, contains('sala B'));
    expect(ScheduleNotification.fromChanges([]), isNull);
  });
  test('multiple changes deduplicate and limit notification payload', () {
    final same = change('Matematyka', 'Usunięto zajęcia');
    expect(ScheduleNotification.fromChanges([same, same])!.title,
        'Usunięto z planu: Matematyka');
    final content = ScheduleNotification.fromChanges(List.generate(
        20,
        (i) =>
            change('Przedmiot $i', List.filled(200, 'szczegóły').join(' '))))!;
    expect(content.title, 'Zmiany w planie: 20');
    expect(content.body.length, lessThanOrEqualTo(240));
    expect(content.details.length, lessThanOrEqualTo(8000));
  });
  test(
      'Android notification has expandable details, private visibility and no empty alerts',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    final service = NotificationService();
    await service.init();
    await service.showScheduleChangedNotification([]);
    expect(calls.where((call) => call.method == 'show'), isEmpty);
    await service.showScheduleChangedNotification(
        [change('Matematyka', 'Sala A → sala B')]);
    final args =
        calls.singleWhere((call) => call.method == 'show').arguments as Map;
    expect(args['title'], contains('Matematyka'));
    expect(args['body'], contains('Sala A → sala B'));
    final platform = args['platformSpecifics'] as Map;
    expect(platform['visibility'], NotificationVisibility.private.index);
    expect((platform['styleInformation'] as Map)['bigText'],
        contains('Sala A → sala B'));
  });
}
