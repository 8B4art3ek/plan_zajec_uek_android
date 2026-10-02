// lib/presentation/screens/settings/settings_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/schedule_entry.dart';
import '../../../domain/entities/subject_filter.dart';
import '../../providers/providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hideResAsync = ref.watch(hideReservationsProvider);
    final filtersAsync = ref.watch(subjectFiltersProvider);
    final colorsAsync = ref.watch(classTypeColorsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Ustawienia')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ---- Reservations ----
          const _SectionTitle(title: 'Filtrowanie'),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: hideResAsync.when(
              loading: () => const ListTile(
                  title: Text('Ukryj rezerwacje',
                      style: TextStyle(color: AppColors.onSurface))),
              error: (_, __) => const SizedBox.shrink(),
              data: (hideRes) => SwitchListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                title: const Text('Ukryj rezerwacje',
                    style: TextStyle(
                        color: AppColors.onSurface,
                        fontWeight: FontWeight.w500)),
                subtitle: const Text('Nie pokazuj wpisow "rezerwacja" w planie',
                    style: TextStyle(
                        color: AppColors.onSurfaceMuted, fontSize: 12)),
                value: hideRes,
                onChanged: (_) =>
                    ref.read(hideReservationsProvider.notifier).toggle(),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ---- Colors ----
          const _SectionTitle(title: 'Kolory typow'),
          const SizedBox(height: 8),
          colorsAsync.when(
            loading: () => const _SettingsCard(
              child: ListTile(
                title: Text('Ladowanie kolorow',
                    style: TextStyle(color: AppColors.onSurface)),
              ),
            ),
            error: (_, __) => const _SettingsCard(
              child: ListTile(
                title: Text('Nie udalo sie wczytac kolorow',
                    style: TextStyle(color: AppColors.error)),
              ),
            ),
            data: (colors) => _ColorSettingsList(colors: colors),
          ),
          const SizedBox(height: 24),

          // ---- Subject filters ----
          Row(
            children: [
              const Expanded(child: _SectionTitle(title: 'Filtry przedmiotow')),
              TextButton.icon(
                onPressed: () => _showAddFilterDialog(context, ref),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Dodaj'),
                style: TextButton.styleFrom(foregroundColor: AppColors.primary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          filtersAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (filters) {
              if (filters.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Text(
                    'Brak filtrow. Dodaj filtr aby ukryc lub pokazac wybrane przedmioty.',
                    style: TextStyle(
                        color: AppColors.onSurfaceMuted, fontSize: 13),
                  ),
                );
              }
              return Column(
                children: filters.map((f) => _FilterTile(filter: f)).toList(),
              );
            },
          ),
          const SizedBox(height: 24),

          // ---- Account ----
          const _SectionTitle(title: 'Konto'),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: const Icon(Icons.logout_rounded, color: AppColors.error),
              title: const Text('Wyloguj sie',
                  style: TextStyle(
                      color: AppColors.error, fontWeight: FontWeight.w500)),
              subtitle: const Text('Usunie dane logowania z urzadzenia',
                  style:
                      TextStyle(color: AppColors.onSurfaceMuted, fontSize: 12)),
              onTap: () => _confirmLogout(context, ref),
            ),
          ),
          const SizedBox(height: 24),

          // ---- App info ----
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Plan Zajec UEK',
                    style: TextStyle(
                        color: AppColors.onSurface,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
                SizedBox(height: 4),
                Text('Wersja 1.0.0',
                    style: TextStyle(
                        color: AppColors.onSurfaceMuted, fontSize: 12)),
                SizedBox(height: 4),
                Text(
                  'Plan pobierany z planzajec.uek.krakow.pl\nOdswiezanie automatyczne co 1 godzine.',
                  style: TextStyle(
                      color: AppColors.onSurfaceMuted,
                      fontSize: 12,
                      height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  void _showAddFilterDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => _AddFilterDialog(widgetRef: ref),
    );
  }

  void _confirmLogout(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Wyloguj sie',
            style: TextStyle(color: AppColors.onSurface)),
        content: const Text(
            'Czy na pewno chcesz sie wylogowac? Dane logowania zostana usuniete.',
            style: TextStyle(color: AppColors.onSurfaceMuted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Anuluj',
                style: TextStyle(color: AppColors.onSurfaceMuted)),
          ),
          TextButton(
            onPressed: () async {
              await ref.read(authServiceProvider).clearCredentials();
              ref.invalidate(credentialsProvider);
              ref.invalidate(isLoggedInProvider);
              if (context.mounted) {
                Navigator.of(context)
                    .pushNamedAndRemoveUntil('/login', (_) => false);
              }
            },
            child:
                const Text('Wyloguj', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final Widget child;

  const _SettingsCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: child,
    );
  }
}

class _ColorSettingsList extends ConsumerWidget {
  final Map<String, Color> colors;

  const _ColorSettingsList({required this.colors});

  static const _palette = [
    Color(0xFF9D6CFF),
    Color(0xFF38BDF8),
    Color(0xFF22D3EE),
    Color(0xFF4ADE80),
    Color(0xFFFFB020),
    Color(0xFFF59E0B),
    Color(0xFFFF6B6B),
    Color(0xFFFF5C8A),
    Color(0xFFFACC15),
    Color(0xFFA78BFA),
    Color(0xFF94A3B8),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _SettingsCard(
      child: Column(
        children: [
          for (int i = 0; i < AppColors.scheduleColorOptions.length; i++) ...[
            _ColorTile(
              option: AppColors.scheduleColorOptions[i],
              color: colors[AppColors.scheduleColorOptions[i].key] ??
                  AppColors.scheduleColorOptions[i].defaultColor,
              onTap: () => _showColorDialog(
                context,
                ref,
                AppColors.scheduleColorOptions[i],
                colors[AppColors.scheduleColorOptions[i].key] ??
                    AppColors.scheduleColorOptions[i].defaultColor,
              ),
            ),
            if (i < AppColors.scheduleColorOptions.length - 1)
              Divider(
                height: 1,
                color: AppColors.onSurfaceMuted.withValues(alpha: 0.08),
                indent: 16,
                endIndent: 16,
              ),
          ],
        ],
      ),
    );
  }

  void _showColorDialog(
    BuildContext context,
    WidgetRef ref,
    ScheduleColorOption option,
    Color currentColor,
  ) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          option.label,
          style: const TextStyle(color: AppColors.onSurface, fontSize: 16),
        ),
        content: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final color in _palette)
              _ColorSwatchButton(
                color: color,
                isSelected: color.toARGB32() == currentColor.toARGB32(),
                onTap: () async {
                  await ref
                      .read(classTypeColorsProvider.notifier)
                      .setColor(option.key, color);
                  if (context.mounted) Navigator.of(context).pop();
                },
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await ref
                  .read(classTypeColorsProvider.notifier)
                  .resetColor(option.key);
              if (context.mounted) Navigator.of(context).pop();
            },
            child: const Text('Domyslny',
                style: TextStyle(color: AppColors.onSurfaceMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Zamknij',
                style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }
}

class _ColorTile extends StatelessWidget {
  final ScheduleColorOption option;
  final Color color;
  final VoidCallback onTap;

  const _ColorTile({
    required this.option,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: _ColorDot(color: color),
      title: Text(
        option.label,
        style: const TextStyle(
          color: AppColors.onSurface,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        _hexColor(color),
        style: const TextStyle(color: AppColors.onSurfaceMuted, fontSize: 12),
      ),
      trailing: const Icon(
        Icons.palette_outlined,
        color: AppColors.onSurfaceMuted,
        size: 20,
      ),
      onTap: onTap,
    );
  }
}

class _ColorDot extends StatelessWidget {
  final Color color;

  const _ColorDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
    );
  }
}

class _ColorSwatchButton extends StatelessWidget {
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _ColorSwatchButton({
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? Colors.white : Colors.transparent,
            width: 2,
          ),
        ),
        child: isSelected
            ? const Icon(Icons.check_rounded, color: Colors.white, size: 22)
            : null,
      ),
    );
  }
}

String _hexColor(Color color) {
  final hex = color.toARGB32().toRadixString(16).padLeft(8, '0');
  return '#${hex.substring(2).toUpperCase()}';
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: AppColors.onSurfaceMuted,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
      ),
    );
  }
}

class _FilterTile extends ConsumerWidget {
  final SubjectFilter filter;
  const _FilterTile({required this.filter});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: filter.isHidden
                ? AppColors.error.withValues(alpha: 0.12)
                : AppColors.success.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            filter.isHidden
                ? Icons.visibility_off_rounded
                : Icons.visibility_rounded,
            color: filter.isHidden ? AppColors.error : AppColors.success,
            size: 18,
          ),
        ),
        title: Text(
          filter.subject,
          style: const TextStyle(
              color: AppColors.onSurface,
              fontWeight: FontWeight.w500,
              fontSize: 14),
        ),
        subtitle: Text(
          '${filter.isHidden ? "Ukryty" : "Widoczny"} — Grupa: ${filter.groupId}',
          style: const TextStyle(color: AppColors.onSurfaceMuted, fontSize: 12),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline_rounded,
              color: AppColors.error, size: 20),
          onPressed: () {
            if (filter.id != null) {
              ref
                  .read(subjectFiltersProvider.notifier)
                  .removeFilter(filter.id!);
            }
          },
        ),
      ),
    );
  }
}

class _AddFilterDialog extends StatefulWidget {
  final WidgetRef widgetRef;
  const _AddFilterDialog({required this.widgetRef});

  @override
  State<_AddFilterDialog> createState() => _AddFilterDialogState();
}

class _AddFilterDialogState extends State<_AddFilterDialog> {
  final _formKey = GlobalKey<FormState>();
  final _subjectCtrl = TextEditingController();
  final _groupIdCtrl = TextEditingController();
  bool _isHidden = true;

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _groupIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final filter = SubjectFilter(
      subject: _subjectCtrl.text.trim(),
      groupId: _groupIdCtrl.text.trim(),
      isHidden: _isHidden,
    );

    await widget.widgetRef
        .read(subjectFiltersProvider.notifier)
        .addFilter(filter);
    widget.widgetRef.invalidate(todayScheduleProvider);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    // Try to populate available groups for hint
    final groups = widget.widgetRef.read(groupsProvider).value ?? [];

    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('Dodaj filtr przedmiotu',
          style: TextStyle(color: AppColors.onSurface, fontSize: 16)),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _subjectCtrl,
              decoration: const InputDecoration(
                labelText: 'Nazwa przedmiotu',
                hintText: 'np. Matematyka',
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Podaj przedmiot' : null,
            ),
            const SizedBox(height: 12),
            if (groups.isNotEmpty)
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Grupa'),
                dropdownColor: AppColors.surfaceVariant,
                items: groups
                    .map((g) => DropdownMenuItem(
                          value: g.groupId,
                          child: Text('${g.groupId} (${g.groupType.label})',
                              style: const TextStyle(
                                  color: AppColors.onSurface, fontSize: 13)),
                        ))
                    .toList(),
                onChanged: (val) {
                  if (val != null) _groupIdCtrl.text = val;
                },
                validator: (v) =>
                    v == null || v.isEmpty ? 'Wybierz grupe' : null,
              )
            else
              TextFormField(
                controller: _groupIdCtrl,
                decoration: const InputDecoration(
                  labelText: 'ID Grupy',
                  hintText: 'np. 239641',
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Podaj ID grupy' : null,
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Ukryj ten przedmiot',
                    style: TextStyle(
                        color: AppColors.onSurface,
                        fontWeight: FontWeight.w500,
                        fontSize: 14),
                  ),
                ),
                Switch(
                  value: _isHidden,
                  onChanged: (v) => setState(() => _isHidden = v),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Anuluj',
              style: TextStyle(color: AppColors.onSurfaceMuted)),
        ),
        ElevatedButton(
          onPressed: _save,
          child: const Text('Zapisz'),
        ),
      ],
    );
  }
}
