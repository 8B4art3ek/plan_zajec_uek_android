import 'group.dart';
import 'schedule_entry.dart';

class UsosImportData {
  final String? pageUrl;
  final String? pageTitle;
  final List<String> deanCodes;
  final List<UsosLanguageGroup> languageGroups;

  const UsosImportData({
    this.pageUrl,
    this.pageTitle,
    required this.deanCodes,
    required this.languageGroups,
  });

  bool get isEmpty => deanCodes.isEmpty && languageGroups.isEmpty;

  String? get fallbackStudyLevel {
    for (final code in deanCodes) {
      final match = RegExp(r'S([12])').firstMatch(code);
      if (match != null) return 'S${match.group(1)}';
    }
    return null;
  }

  List<UsosImportTarget> toTargets() {
    final targets = <UsosImportTarget>[
      for (final code in deanCodes)
        UsosImportTarget(
          groupType: GroupType.dean,
          sourceLabel: code,
          scheduleCodeCandidates: [code],
        ),
    ];

    for (final group in languageGroups) {
      targets.add(
        UsosImportTarget(
          groupType: GroupType.language,
          sourceLabel: group.label,
          scheduleCodeCandidates: group.scheduleCodeCandidates(
            fallbackStudyLevel,
          ),
          includeAllMatches: group.usosCourseCode != null,
        ),
      );
    }

    return targets;
  }
}

class UsosLanguageGroup {
  final String languageName;
  final List<String> languageCodeCandidates;
  final String level;
  final int groupNumber;
  final int? semester;
  final String? studyLevel;
  final String? usosCourseCode;
  final String sourceText;

  const UsosLanguageGroup({
    required this.languageName,
    required this.languageCodeCandidates,
    required this.level,
    required this.groupNumber,
    this.semester,
    this.studyLevel,
    this.usosCourseCode,
    required this.sourceText,
  });

  String get label {
    final semesterPart = semester == null ? '' : ', sem. $semester';
    final groupPart = groupNumber == 0 ? '' : ', gr. $groupNumber';
    return '$languageName $level$groupPart$semesterPart';
  }

  List<String> scheduleCodeCandidates(String? fallbackStudyLevel) {
    if (usosCourseCode != null) return [usosCourseCode!];
    final levels = _unique([studyLevel, fallbackStudyLevel, 'S1', 'S2']);
    final semesters = semester == null ? const [1, 2, 3, 4, 5, 6] : [semester!];
    final groupCode = groupNumber.toString().padLeft(2, '0');
    final normalizedLevel = level.toUpperCase().replaceAll(' ', '');
    final codes = <String>[];

    for (final studyLevel in levels) {
      for (final semester in semesters) {
        final studyYear = ((semester + 1) ~/ 2).clamp(1, 5);
        for (final languageCode in languageCodeCandidates) {
          codes.add(
            'CJ-$studyLevel-$studyYear/$semester-'
            '${languageCode.toUpperCase()}.$normalizedLevel-$groupCode',
          );
        }
      }
    }

    return _unique(codes);
  }
}

class UsosImportTarget {
  final GroupType groupType;
  final String sourceLabel;
  final List<String> scheduleCodeCandidates;
  final bool includeAllMatches;

  const UsosImportTarget({
    required this.groupType,
    required this.sourceLabel,
    required this.scheduleCodeCandidates,
    this.includeAllMatches = false,
  });
}

class ResolvedUsosGroup {
  final GroupType groupType;
  final String sourceLabel;
  final String scheduleCode;
  final String scheduleId;
  final String scheduleLabel;

  const ResolvedUsosGroup({
    required this.groupType,
    required this.sourceLabel,
    required this.scheduleCode,
    required this.scheduleId,
    required this.scheduleLabel,
  });

  Group toGroup() => Group(
        groupId: scheduleId,
        groupType: groupType,
        name: scheduleCode,
        isEnabled: true,
      );
}

class UnresolvedUsosGroup {
  final GroupType groupType;
  final String sourceLabel;
  final List<String> scheduleCodeCandidates;

  const UnresolvedUsosGroup({
    required this.groupType,
    required this.sourceLabel,
    required this.scheduleCodeCandidates,
  });
}

class UsosImportFailure {
  final ResolvedUsosGroup group;
  final String message;

  const UsosImportFailure({
    required this.group,
    required this.message,
  });
}

class UsosImportResult {
  final List<ResolvedUsosGroup> imported;
  final List<UnresolvedUsosGroup> unresolved;
  final List<UsosImportFailure> refreshFailures;

  const UsosImportResult({
    required this.imported,
    required this.unresolved,
    this.refreshFailures = const [],
  });

  int get importedCount => imported.length;
  bool get hasProblems => unresolved.isNotEmpty || refreshFailures.isNotEmpty;

  UsosImportResult copyWith({
    List<ResolvedUsosGroup>? imported,
    List<UnresolvedUsosGroup>? unresolved,
    List<UsosImportFailure>? refreshFailures,
  }) {
    return UsosImportResult(
      imported: imported ?? this.imported,
      unresolved: unresolved ?? this.unresolved,
      refreshFailures: refreshFailures ?? this.refreshFailures,
    );
  }
}

List<T> _unique<T>(Iterable<T?> values) {
  final seen = <T>{};
  final result = <T>[];
  for (final value in values) {
    if (value == null) continue;
    if (seen.add(value)) result.add(value);
  }
  return result;
}
