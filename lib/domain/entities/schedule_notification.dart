import 'schedule_change.dart';
import 'change_summary.dart';

class ScheduleNotification {
  const ScheduleNotification(
      {required this.title, required this.body, required this.details});
  final String title;
  final String body;
  final String details;

  static ScheduleNotification? fromChanges(List<ScheduleChange> changes) {
    if (changes.isEmpty) return null;
    final unique = {
      for (final change in ChangeSummary.coalesceMoves(changes))
        '${change.subject}\n${change.description}': change
    }.values.toList();
    String limit(String value, int max) =>
        value.length > max ? '${value.substring(0, max - 1)}…' : value;
    final first = unique.first;
    final summary = ChangeSummary.from(first);
    final details = [
      for (final change in unique.take(10))
        '${change.subject.isEmpty ? 'Zajęcia' : change.subject}\n${ChangeSummary.from(change).details}',
      if (unique.length > 10)
        'Pozostałe zmiany: ${unique.length - 10}. Pełna lista w aplikacji.',
    ].join('\n\n');
    return ScheduleNotification(
      title: unique.length == 1
          ? '${summary.label}: ${first.subject.isEmpty ? 'zajęcia' : first.subject}'
          : 'Zmiany w planie: ${unique.length}',
      body: limit(
          unique.length == 1
              ? summary.before == null
                  ? summary.after
                  : '${summary.before} → ${summary.after}${summary.context.isEmpty ? '' : '\n${summary.context}'}'
              : [
                  for (final kind in ChangeKind.values)
                    if (unique.any(
                        (change) => ChangeSummary.from(change).kind == kind))
                      '${switch (kind) {
                        ChangeKind.added => 'Dodano',
                        ChangeKind.removed => 'Usunięto',
                        ChangeKind.updated => 'Zmieniono'
                      }}: ${unique.where((change) => ChangeSummary.from(change).kind == kind).length}'
                ].join(' · '),
          240),
      details: limit(details, 8000),
    );
  }
}
