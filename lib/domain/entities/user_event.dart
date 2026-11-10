// lib/domain/entities/user_event.dart

class UserEvent {
  static const defaultEventType = 'Wydarzenie';

  final int? id;
  final String title;
  final String eventType;
  final String? description;
  final DateTime date;
  final String startTime;
  final String endTime;
  final String? room;

  const UserEvent({
    this.id,
    required this.title,
    this.eventType = defaultEventType,
    this.description,
    required this.date,
    required this.startTime,
    required this.endTime,
    this.room,
  });
}
