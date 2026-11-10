import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_identity.dart';
import '../../providers/app_update_provider.dart';
import '../../widgets/app_scroll_view.dart';

class AppUpdatesScreen extends ConsumerStatefulWidget {
  const AppUpdatesScreen({super.key});

  @override
  ConsumerState<AppUpdatesScreen> createState() => _AppUpdatesScreenState();
}

class _AppUpdatesScreenState extends ConsumerState<AppUpdatesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final updates = ref.read(appUpdateProvider);
      if (!updates.checked && !updates.busy) updates.check();
    });
  }

  @override
  Widget build(BuildContext context) {
    final updates = ref.watch(appUpdateProvider);
    final release = updates.release;
    final installed = updates.installed;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Aktualizacje aplikacji'),
        actions: [
          IconButton(
            tooltip: 'Sprawdź aktualizacje',
            onPressed: updates.busy ? null : updates.check,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: AppScrollView(
            child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(children: [
              Image.asset(appIconAsset, width: 56, height: 56),
              const SizedBox(width: 16),
              Expanded(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(appName, style: Theme.of(context).textTheme.titleMedium),
                  if (installed != null)
                    Text('Wersja ${installed.version}'),
                ],
              )),
            ]),
            const SizedBox(height: 28),
            if (updates.checking) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 12),
              const Text('Sprawdzanie aktualizacji…'),
            ] else if (updates.available && release != null) ...[
              Text('Dostępna wersja ${release.version}',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text('Rozmiar: ${_mb(release.size)} MB'),
              if (release.notes.trim().isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text('Co nowego',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text(release.notes),
              ],
              const SizedBox(height: 24),
              if (updates.downloading) ...[
                LinearProgressIndicator(value: updates.received / release.size),
                const SizedBox(height: 12),
                Text(updates.received == release.size
                    ? 'Sprawdzanie instalatora…'
                    : '${_mb(updates.received)} / ${_mb(release.size)} MB'),
                TextButton.icon(
                    onPressed: updates.cancel,
                    icon: const Icon(Icons.close),
                    label: const Text('Anuluj pobieranie')),
              ] else if (updates.ready) ...[
                if (updates.permissionNeeded) ...[
                  const Text(
                      'Zezwól aplikacji $appName na instalowanie aktualizacji w ustawieniach Androida, wróć tutaj i naciśnij „Zainstaluj”.'),
                  const SizedBox(height: 16),
                ],
                FilledButton.icon(
                  onPressed: updates.installing ? null : updates.install,
                  icon: const Icon(Icons.system_update_rounded),
                  label: const Text('Zainstaluj'),
                ),
              ] else
                FilledButton.icon(
                  onPressed: updates.download,
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Pobierz aktualizację'),
                ),
            ] else if (updates.error == null && updates.checked)
              Text(release == null
                  ? 'Nie opublikowano jeszcze instalatora aktualizacji.'
                  : 'Masz aktualną wersję aplikacji.'),
            if (updates.error != null) ...[
              const SizedBox(height: 16),
              Text(updates.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        )),
      ),
    );
  }

  String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);
}
