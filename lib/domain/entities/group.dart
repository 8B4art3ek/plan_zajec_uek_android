// lib/domain/entities/group.dart

import 'schedule_entry.dart';

class Group {
  final int? id;
  final String groupId;
  final GroupType groupType;
  final String? name;
  final bool isEnabled;

  const Group({
    this.id,
    required this.groupId,
    required this.groupType,
    this.name,
    this.isEnabled = true,
  });

  Group copyWith({
    int? id,
    String? groupId,
    GroupType? groupType,
    String? name,
    bool? isEnabled,
  }) {
    return Group(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      groupType: groupType ?? this.groupType,
      name: name ?? this.name,
      isEnabled: isEnabled ?? this.isEnabled,
    );
  }

  String get displayName => name ?? groupId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Group &&
          runtimeType == other.runtimeType &&
          groupId == other.groupId;

  @override
  int get hashCode => groupId.hashCode;
}
