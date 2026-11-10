import 'schedule_change.dart';

enum ChangeKind { added, removed, updated }

class ChangeSummary {
  const ChangeSummary(
      {required this.kind,
      required this.context,
      required this.before,
      required this.after});
  final ChangeKind kind;
  final String context;
  final String? before;
  final String after;
  String get label => switch (kind) {
        ChangeKind.added => 'Dodano zajęcia',
        ChangeKind.removed => 'Usunięto z planu',
        ChangeKind.updated => 'Zmieniono zajęcia',
      };

  factory ChangeSummary.from(ScheduleChange change) {
    final lines = change.description.split('\n');
    final first = lines.first.toLowerCase();
    final isMove =
        RegExp(r'przeniesion[eo]|przeniesienie', caseSensitive: false)
            .hasMatch(change.description);
    final kind = first.startsWith('dodano') && !isMove
        ? ChangeKind.added
        : first.startsWith('usuni')
            ? ChangeKind.removed
            : ChangeKind.updated;
    String? read(String prefix) => lines
        .where((line) => line.startsWith(prefix))
        .map((line) => line.substring(prefix.length).trim())
        .firstOrNull;
    List<String> parts(String value) => value
        .split(' · ')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty && part != change.subject)
        .toList();
    final before = read('Przed:');
    final after = read('Teraz:');
    if (before != null && after != null) {
      final old = parts(before);
      final current = parts(after);
      final removed = old.where((part) => !current.contains(part)).toList();
      final added = current.where((part) => !old.contains(part)).toList();
      final when = current
          .where((part) =>
              old.contains(part) && RegExp(r'\d{1,2}[.:]\d{2}').hasMatch(part))
          .join(' · ');
      return ChangeSummary(
          kind: kind,
          context: when,
          before: removed.isEmpty && added.isNotEmpty
              ? 'Brak danych'
              : (removed.isEmpty ? old : removed).join(' · '),
          after: added.isEmpty && removed.isNotEmpty
              ? 'Brak danych'
              : (added.isEmpty ? current : added).join(' · '));
    }
    final detail =
        lines.length > 1 ? lines.skip(1).join('\n') : change.description;
    return ChangeSummary(
        kind: kind,
        context: '',
        before: null,
        after: parts(detail).join(' · '));
  }

  /// Coalesce pending move alerts produced by older app versions, without
  /// changing the journal IDs acknowledged by the caller.
  static List<ScheduleChange> coalesceMoves(List<ScheduleChange> changes) {
    final replacements = <ScheduleChange, ScheduleChange>{};
    final consumed = <ScheduleChange>{};
    for (final change in changes) {
      if (!change.description.startsWith('Dodano')) continue;
      final target =
          RegExp(r'Przeniesione:\s*(\d{2}\.\d{2}\.\d{4})(?:\s+(\d{2}:\d{2}))?')
              .firstMatch(change.description);
      if (target == null) continue;
      final candidates = changes
          .where((other) =>
              !identical(other, change) &&
              !consumed.contains(other) &&
              other.groupId == change.groupId &&
              other.subject == change.subject &&
              other.detectedAt == change.detectedAt &&
              other.description.startsWith('Dodano') &&
              !RegExp(r'przeniesion[eo]|przeniesienie', caseSensitive: false)
                  .hasMatch(other.description) &&
              other.description
                  .split(' · ')
                  .any((part) => part.trim() == target.group(1)) &&
              (target.group(2) == null ||
                  other.description.contains('${target.group(2)}–')))
          .toList();
      if (candidates.length != 1) continue;
      final destination = candidates.single;
      final origin = change.description
          .split('\n')
          .skip(1)
          .join('\n')
          .split(' · ')
          .where((part) => !part.toLowerCase().startsWith('przenies'))
          .join(' · ');
      final after = destination.description.split('\n').skip(1).join('\n');
      replacements[change] = ScheduleChange(
          id: change.id,
          groupId: change.groupId,
          subject: change.subject,
          detectedAt: change.detectedAt,
          description: 'Zmieniono zajęcia\nPrzed: $origin\nTeraz: $after');
      consumed.add(destination);
    }
    return [
      for (final change in changes)
        if (!consumed.contains(change)) replacements[change] ?? change
    ];
  }

  String get details => [
        label,
        if (context.isNotEmpty) context,
        if (before != null) 'Było: $before',
        if (after.isNotEmpty) '${before == null ? '' : 'Teraz: '}$after'
      ].join('\n');
}
