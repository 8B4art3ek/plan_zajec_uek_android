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
}
