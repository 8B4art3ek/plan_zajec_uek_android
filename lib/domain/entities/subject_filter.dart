// lib/domain/entities/subject_filter.dart

class SubjectFilter {
  final int? id;
  final String subject;
  final String groupId; // which group's subject is hidden/shown
  final bool isHidden;

  const SubjectFilter({
    this.id,
    required this.subject,
    required this.groupId,
    required this.isHidden,
  });

  SubjectFilter copyWith({
    int? id,
    String? subject,
    String? groupId,
    bool? isHidden,
  }) {
    return SubjectFilter(
      id: id ?? this.id,
      subject: subject ?? this.subject,
      groupId: groupId ?? this.groupId,
      isHidden: isHidden ?? this.isHidden,
    );
  }
}
