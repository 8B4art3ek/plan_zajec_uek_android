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

  DateTime get startDateTime {
    final parts = startTime.split(':');
    return DateTime(
      date.year,
      date.month,
      date.day,
      int.parse(parts[0]),
      int.parse(parts[1]),
    );
  }

  DateTime get endDateTime {
    final parts = endTime.split(':');
    return DateTime(
      date.year,
      date.month,
      date.day,
      int.parse(parts[0]),
      int.parse(parts[1]),
    );
  }

  UserEvent copyWith({
    int? id,
    String? title,
    String? eventType,
    String? description,
    DateTime? date,
    String? startTime,
    String? endTime,
    String? room,
  }) {
    return UserEvent(
      id: id ?? this.id,
      title: title ?? this.title,
      eventType: eventType ?? this.eventType,
      description: description ?? this.description,
      date: date ?? this.date,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      room: room ?? this.room,
    );
  }
}
