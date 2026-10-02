// lib/domain/entities/schedule_entry.dart

class ScheduleEntry {
  final String id;
  final String subject;
  final String classType;
  final String lecturer;
  final String room;
  final DateTime date;
  final String startTime;
  final String endTime;
  final String weekday;
  final double durationHours;
  final String groupId;
  final GroupType groupType;

  // Moved class fields
  final bool isMoved;
  final DateTime? originalDate;
  final String? originalStartTime;
  final String? originalEndTime;
  final DateTime? newDate;
  final String? newStartTime;
  final String? newEndTime;

  const ScheduleEntry({
    required this.id,
    required this.subject,
    required this.classType,
    required this.lecturer,
    required this.room,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.weekday,
    required this.durationHours,
    required this.groupId,
    required this.groupType,
    this.isMoved = false,
    this.originalDate,
    this.originalStartTime,
    this.originalEndTime,
    this.newDate,
    this.newStartTime,
    this.newEndTime,
  });

  bool get isReservation => classType.toLowerCase().contains('rezerwacja');

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

  ScheduleEntry copyWith({
    String? id,
    String? subject,
    String? classType,
    String? lecturer,
    String? room,
    DateTime? date,
    String? startTime,
    String? endTime,
    String? weekday,
    double? durationHours,
    String? groupId,
    GroupType? groupType,
    bool? isMoved,
    DateTime? originalDate,
    String? originalStartTime,
    String? originalEndTime,
    DateTime? newDate,
    String? newStartTime,
    String? newEndTime,
  }) {
    return ScheduleEntry(
      id: id ?? this.id,
      subject: subject ?? this.subject,
      classType: classType ?? this.classType,
      lecturer: lecturer ?? this.lecturer,
      room: room ?? this.room,
      date: date ?? this.date,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      weekday: weekday ?? this.weekday,
      durationHours: durationHours ?? this.durationHours,
      groupId: groupId ?? this.groupId,
      groupType: groupType ?? this.groupType,
      isMoved: isMoved ?? this.isMoved,
      originalDate: originalDate ?? this.originalDate,
      originalStartTime: originalStartTime ?? this.originalStartTime,
      originalEndTime: originalEndTime ?? this.originalEndTime,
      newDate: newDate ?? this.newDate,
      newStartTime: newStartTime ?? this.newStartTime,
      newEndTime: newEndTime ?? this.newEndTime,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScheduleEntry &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

enum GroupType { dean, language, pe }

extension GroupTypeExtension on GroupType {
  String get label {
    switch (this) {
      case GroupType.dean:
        return 'Dziekańska';
      case GroupType.language:
        return 'Językowa';
      case GroupType.pe:
        return 'WF';
    }
  }

  String get dbValue {
    return name;
  }

  static GroupType fromString(String value) {
    return GroupType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => GroupType.dean,
    );
  }
}
