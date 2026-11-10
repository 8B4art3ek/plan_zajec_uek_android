import 'package:flutter/material.dart';
import '../../data/datasources/startup_service.dart';
import '../../domain/entities/schedule_change.dart';
import '../../domain/entities/change_summary.dart';

enum GroupSetupChoice { usos, manual }

Future<GroupSetupChoice?> showGroupSetupChoice(BuildContext context) =>
    showDialog<GroupSetupChoice>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
              scrollable: true,
              title: const Text('Jak dodać grupy?'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                ListTile(
                    leading: const Icon(Icons.cloud_download_outlined),
                    title: const Text('Importuj z USOS'),
                    onTap: () =>
                        Navigator.of(context).pop(GroupSetupChoice.usos)),
                ListTile(
                    leading: const Icon(Icons.edit_outlined),
                    title: const Text('Dodaj ręcznie po ID'),
                    onTap: () =>
                        Navigator.of(context).pop(GroupSetupChoice.manual)),
              ]),
            ));

Future<bool> showReleaseNews(
        BuildContext context, StartupRelease release) async =>
    await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              scrollable: true,
              title: Text('Co nowego w ${release.installed.version}'),
              content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final note in release.notes)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(note))
                  ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Rozumiem'))
              ],
            )) ??
    false;

Future<bool> showScheduleChanges(
        BuildContext context, List<ScheduleChange> changes) async =>
    await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              scrollable: true,
              title: const Text('Zmiany w planie'),
              content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final change in ChangeSummary.coalesceMoves(changes))
                      _ChangeTile(change: change),
                  ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Rozumiem'))
              ],
            )) ??
    false;

class _ChangeTile extends StatelessWidget {
  const _ChangeTile({required this.change});
  final ScheduleChange change;
  @override
  Widget build(BuildContext context) {
    final summary = ChangeSummary.from(change);
    final (color, icon) = switch (summary.kind) {
      ChangeKind.added => (Colors.green.shade600, Icons.add_circle_outline),
      ChangeKind.removed => (Colors.red.shade400, Icons.event_busy_outlined),
      ChangeKind.updated => (Colors.blue.shade400, Icons.swap_horiz_rounded),
    };
    return Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(summary.label,
                      style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w600,
                          fontSize: 13))),
            ]),
            const SizedBox(height: 6),
            Text(change.subject.isEmpty ? 'Zajęcia' : change.subject,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            if (summary.context.isNotEmpty)
              Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(summary.context,
                      style: Theme.of(context).textTheme.bodySmall)),
            const SizedBox(height: 8),
            if (summary.before != null) ...[
              const Text('BYŁO', style: TextStyle(fontSize: 11)),
              Text(summary.before!,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      decoration: TextDecoration.lineThrough)),
              const SizedBox(height: 6),
              const Text('TERAZ',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
            ],
            Text(summary.after,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            const Divider(height: 1),
          ],
        ));
  }
}
