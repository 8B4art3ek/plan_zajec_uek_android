import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../providers/providers.dart';
import '../../widgets/app_scroll_view.dart';

class CustomColorsScreen extends ConsumerWidget {
  const CustomColorsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(customThemeColorsProvider);
    final saved = colors.valueOrNull ?? const <String, Color>{};
    final entries = {
      'primary': ('Kolor główny', saved['primary'] ?? AppColors.primary),
      'secondary': (
        'Kolor dodatkowy',
        saved['secondary'] ?? AppColors.secondary
      ),
      'background': (
        'Tło aplikacji',
        saved['background'] ?? AppColors.background
      ),
      'surface': ('Tło kafelków', saved['surface'] ?? AppColors.surface),
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Własne kolory'), actions: [
        IconButton(
          tooltip: 'Zapisz motyw',
          icon: const Icon(Icons.save_outlined),
          onPressed: !colors.hasValue
              ? null
              : () async {
                  try {
                    await ref
                        .read(customThemeColorsProvider.notifier)
                        .saveTheme({
                      for (final entry in entries.entries)
                        entry.key: entry.value.$2
                    });
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Zapisano motyw Własny.')));
                    }
                  } catch (_) {
                    if (context.mounted) _error(context);
                  }
                },
        ),
        IconButton(
          tooltip: 'Przywróć kolory motywu',
          icon: const Icon(Icons.restore_rounded),
          onPressed: colors.hasValue
              ? () async {
                  try {
                    await ref.read(customThemeColorsProvider.notifier).reset();
                  } catch (_) {
                    if (context.mounted) _error(context);
                  }
                }
              : null,
        ),
      ]),
      body: colors.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
            child: TextButton(
                onPressed: () => ref.invalidate(customThemeColorsProvider),
                child: const Text('Ponów wczytywanie kolorów'))),
        data: (_) => AppScrollView(
            child: ListView(children: [
          for (final entry in entries.entries)
            ListTile(
              leading: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                      color: entry.value.$2,
                      borderRadius: BorderRadius.circular(6),
                      border:
                          Border.all(color: Theme.of(context).dividerColor))),
              title: Text(entry.value.$1),
              subtitle: Text(
                  '#${entry.value.$2.toARGB32().toRadixString(16).substring(2).toUpperCase()}'),
              trailing: const Icon(Icons.palette_outlined),
              onTap: () async {
                final color = await showDialog<Color>(
                    context: context,
                    builder: (_) => _PaletteDialog(
                        title: entry.value.$1, color: entry.value.$2));
                if (color == null) return;
                try {
                  await ref
                      .read(customThemeColorsProvider.notifier)
                      .setColor(entry.key, color);
                } catch (_) {
                  if (context.mounted) _error(context);
                }
              },
            ),
        ])),
      ),
    );
  }

  static void _error(BuildContext context) =>
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Nie udało się zapisać kolorów. Spróbuj ponownie.')));
}

class _PaletteDialog extends StatefulWidget {
  const _PaletteDialog({required this.title, required this.color});
  final String title;
  final Color color;
  @override
  State<_PaletteDialog> createState() => _PaletteDialogState();
}

class _PaletteDialogState extends State<_PaletteDialog> {
  late HSVColor color = HSVColor.fromColor(widget.color);
  static const presets = [
    0xFF6C63FF,
    0xFF1976D2,
    0xFF008577,
    0xFFD13A64,
    0xFFE8B75C,
    0xFF121212,
    0xFF222225,
    0xFFF4F4F6,
    0xFFFFFFFF
  ];

  @override
  Widget build(BuildContext context) => AlertDialog(
        scrollable: true,
        title: Text(widget.title),
        content: SizedBox(
            width: 320,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  height: 64, width: double.infinity, color: color.toColor()),
              const SizedBox(height: 16),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final value in presets)
                  Tooltip(
                      message:
                          '#${value.toRadixString(16).substring(2).toUpperCase()}',
                      child: Semantics(
                          button: true,
                          label:
                              'Kolor #${value.toRadixString(16).substring(2)}',
                          child: InkWell(
                            onTap: () => setState(
                                () => color = HSVColor.fromColor(Color(value))),
                            child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                    color: Color(value),
                                    border: Border.all(
                                        color: Theme.of(context).dividerColor),
                                    borderRadius: BorderRadius.circular(6))),
                          ))),
              ]),
              const SizedBox(height: 12),
              const Text('Odcień'),
              Slider(
                  value: color.hue,
                  min: 0,
                  max: 360,
                  semanticFormatterCallback: (v) => '${v.round()} stopni',
                  onChanged: (v) => setState(() => color = color.withHue(v))),
              const Text('Nasycenie'),
              Slider(
                  value: color.saturation,
                  onChanged: (v) =>
                      setState(() => color = color.withSaturation(v))),
              const Text('Jasność'),
              Slider(
                  value: color.value,
                  onChanged: (v) => setState(() => color = color.withValue(v))),
            ])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Anuluj')),
          FilledButton(
              onPressed: () => Navigator.pop(context, color.toColor()),
              child: const Text('Zapisz')),
        ],
      );
}
