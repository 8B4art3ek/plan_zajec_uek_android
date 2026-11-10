import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/app_identity.dart';
import '../../../core/refresh_settings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/schedule_entry.dart';
import '../../../domain/entities/subject_filter.dart';
import '../../../domain/entities/university.dart';
import '../../providers/providers.dart';
import '../../providers/app_update_provider.dart';
import '../../widgets/app_scroll_view.dart';
import '../../widgets/failure_view.dart';
import '../groups/groups_screen.dart';
import '../search/search_screen.dart';
import 'app_updates_screen.dart';
import 'custom_colors_screen.dart';

void _openSettingsPage(BuildContext context, Widget page) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

class SettingsScreen extends ConsumerWidget {
  SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(groupsProvider);
    final filters = ref.watch(subjectFiltersProvider);
    final installed = ref.watch(appUpdateProvider).installed;
    final refresh = ref.watch(refreshMinutesProvider);
    final theme =
        ref.watch(appThemeProvider).valueOrNull ?? AppThemeKind.midnight;
    final university =
        ref.watch(universityProvider).valueOrNull ?? University.uek;
    return Scaffold(
      appBar: AppBar(title: const Text('Więcej')),
      body: AppScrollView(
          child: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 32),
        children: [
          ListTile(
            leading: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(appIconAsset, width: 44, height: 44)),
            title: Text(university.shortName,
                style: Theme.of(context).textTheme.titleLarge),
            subtitle: Text(university.name),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          ),
          _MenuSection(title: 'Plan zajęć', children: [
            _MenuRow(
                icon: Icons.groups_outlined,
                title: 'Moje grupy',
                subtitle: groups.when(
                    data: (items) =>
                        'Aktywne: ${items.where((item) => item.isEnabled).length} · Wszystkie: ${items.length}',
                    loading: () => null,
                    error: (_, __) => 'Nie wczytano grup'),
                onTap: () => _openSettingsPage(context, GroupsScreen())),
            _MenuRow(
                icon: Icons.filter_alt_outlined,
                title: 'Filtry planu',
                subtitle: filters.when(
                    data: (items) =>
                        'Ukryte przedmioty: ${items.where((item) => item.isHidden).length}',
                    loading: () => null,
                    error: (_, __) => 'Nie wczytano filtrów'),
                onTap: () =>
                    _openSettingsPage(context, const PlanFiltersScreen())),
            _MenuRow(
                icon: Icons.meeting_room_outlined,
                title: 'Plany sal',
                onTap: () => _openSettingsPage(
                    context, const SearchScreen(initialTab: 2))),
            _MenuRow(
                icon: Icons.person_search_outlined,
                title: 'Plany prowadzących',
                onTap: () => _openSettingsPage(
                    context, const SearchScreen(initialTab: 1))),
          ]),
          _MenuSection(title: 'Wygląd', children: [
            _MenuRow(
                icon: Icons.palette_outlined,
                title: 'Motyw aplikacji',
                subtitle: theme.label,
                onTap: () => _openSettingsPage(context, ThemeSettingsScreen())),
            _MenuRow(
                icon: Icons.color_lens_outlined,
                title: 'Kolory typów zajęć',
                onTap: () =>
                    _openSettingsPage(context, ClassTypeColorsScreen())),
          ]),
          _MenuSection(title: 'Aplikacja', children: [
            _MenuRow(
                icon: Icons.sync_outlined,
                title: 'Odświeżanie planu',
                subtitle: refresh.when(
                    data: RefreshSettings.label,
                    loading: () => null,
                    error: (_, __) => 'Nie wczytano ustawień'),
                onTap: () =>
                    _openSettingsPage(context, const RefreshSettingsScreen())),
            _MenuRow(
                icon: Icons.system_update_outlined,
                title: 'Aktualizacje aplikacji',
                subtitle:
                    installed == null ? null : 'Wersja ${installed.version}',
                onTap: () =>
                    _openSettingsPage(context, const AppUpdatesScreen())),
          ]),
          _MenuSection(title: 'Konto', children: [
            ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              leading: Icon(Icons.logout_rounded, color: AppColors.error),
              title:
                  Text('Wyloguj się', style: TextStyle(color: AppColors.error)),
              onTap: () => _confirmLogout(context, ref),
            ),
          ]),
          const Padding(
              padding: EdgeInsets.fromLTRB(20, 24, 20, 0),
              child: Text(appName)),
        ],
      )),
    );
  }

  void _confirmLogout(BuildContext context, WidgetRef ref) {
    showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: const Text('Wylogować się?'),
              content: const Text(
                  'Zapisany login i hasło zostaną usunięte z urządzenia.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Anuluj')),
                TextButton(
                    onPressed: () async {
                      try {
                        await ref.read(authServiceProvider).clearCredentials();
                        ref.invalidate(remoteDatasourceProvider);
                        ref.invalidate(credentialsProvider);
                        ref.invalidate(isLoggedInProvider);
                        if (dialogContext.mounted) {
                          Navigator.of(dialogContext)
                              .pushNamedAndRemoveUntil('/login', (_) => false);
                        }
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                              content: Text(
                                  'Nie udało się wylogować. Spróbuj ponownie.')));
                        }
                      }
                    },
                    child: const Text('Wyloguj')),
              ],
            ));
  }
}

class _MenuSection extends StatelessWidget {
  const _MenuSection({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 20),
        Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(color: AppColors.onSurfaceMuted))),
        ...children,
        const Divider(height: 1, indent: 20, endIndent: 20),
      ]);
}

class _MenuRow extends StatelessWidget {
  const _MenuRow(
      {required this.icon,
      required this.title,
      required this.onTap,
      this.subtitle});
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        leading: Icon(icon, color: AppColors.onSurfaceMuted),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle!),
        trailing: const Icon(Icons.chevron_right_rounded, size: 20),
        onTap: onTap,
      );
}

class PlanFiltersScreen extends ConsumerWidget {
  const PlanFiltersScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reservations = ref.watch(hideReservationsProvider);
    final filters = ref.watch(subjectFiltersProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Filtry planu'), actions: [
        IconButton(
            tooltip: 'Dodaj filtr',
            icon: const Icon(Icons.add_rounded),
            onPressed: () => showDialog<void>(
                context: context, builder: (_) => const _AddFilterDialog())),
      ]),
      body: AppScrollView(
          child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
            reservations.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => TextButton(
                  onPressed: () => ref.invalidate(hideReservationsProvider),
                  child: const Text('Ponów wczytywanie rezerwacji')),
              data: (hidden) => SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Ukryj rezerwacje'),
                  value: hidden,
                  onChanged: (_) async {
                    try {
                      await ref
                          .read(hideReservationsProvider.notifier)
                          .toggle();
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content:
                                    Text('Nie udało się zapisać ustawienia.')));
                      }
                    }
                  }),
            ),
            const Divider(height: 32),
            Text('Przedmioty', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            filters.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => FailureView(
                  error: error,
                  onRetry: () => ref.invalidate(subjectFiltersProvider)),
              data: (items) => items.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text('Brak filtrów przedmiotów.'))
                  : Column(children: [
                      for (final filter in items) _FilterTile(filter: filter)
                    ]),
            ),
          ])),
    );
  }
}

class RefreshSettingsScreen extends ConsumerWidget {
  const RefreshSettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(title: const Text('Odświeżanie planu')),
        body: ref.watch(refreshMinutesProvider).when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => FailureView(
                  error: error,
                  onRetry: () => ref.invalidate(refreshMinutesProvider)),
              data: (minutes) => AppScrollView(
                  child: RadioGroup<int>(
                groupValue: minutes,
                onChanged: (value) async {
                  if (value == null) return;
                  try {
                    await ref
                        .read(refreshMinutesProvider.notifier)
                        .setMinutes(value);
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text(
                              'Nie udało się zmienić odświeżania. Spróbuj ponownie.')));
                    }
                  }
                },
                child: ListView(
                    padding: const EdgeInsets.only(top: 8, bottom: 32),
                    children: [
                      for (final value in RefreshSettings.options)
                        RadioListTile<int>(
                            value: value,
                            title: Text(RefreshSettings.label(value))),
                    ]),
              )),
            ),
      );
}

class ThemeSettingsScreen extends ConsumerWidget {
  ThemeSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedTheme =
        ref.watch(appThemeProvider).valueOrNull ?? AppThemeKind.midnight;
    final customColors =
        ref.watch(customThemeColorsProvider).valueOrNull ?? const {};

    return Scaffold(
      appBar: AppBar(title: Text('Motyw aplikacji')),
      body: AppScrollView(
          child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: AppThemeKind.values.length,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, indent: 16, endIndent: 16),
        itemBuilder: (context, index) {
          final theme = AppThemeKind.values[index];
          return ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: Icon(
              theme == selectedTheme
                  ? Icons.check_circle_rounded
                  : Icons.circle_outlined,
              color: theme == selectedTheme
                  ? AppColors.primary
                  : AppColors.onSurfaceMuted,
            ),
            title: Text(
              theme.label,
              style: TextStyle(
                color: AppColors.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            trailing: theme == AppThemeKind.custom
                ? IconButton(
                    tooltip: 'Edytuj własny motyw',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const CustomColorsScreen())),
                  )
                : null,
            onTap: () async {
              if (theme == AppThemeKind.custom && customColors.isEmpty) {
                await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const CustomColorsScreen()));
                return;
              }
              try {
                await ref.read(appThemeProvider.notifier).setTheme(theme);
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text(
                          'Nie udało się zmienić motywu. Spróbuj ponownie.')));
                }
              }
            },
          );
        },
      )),
    );
  }
}

class ClassTypeColorsScreen extends ConsumerWidget {
  ClassTypeColorsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorsAsync = ref.watch(classTypeColorsProvider);
    return Scaffold(
      appBar: AppBar(title: Text('Kolory typów zajęć')),
      body: colorsAsync.when(
        loading: () => Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: Text('Nie udało się wczytać kolorów.'),
        ),
        data: (colors) => AppScrollView(
            child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [_ColorSettingsList(colors: colors)],
        )),
      ),
    );
  }
}

class _ColorSettingsList extends ConsumerWidget {
  final Map<String, Color> colors;

  _ColorSettingsList({required this.colors});

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
    return Column(
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
          style: TextStyle(color: AppColors.onSurface, fontSize: 16),
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
            child: Text('Domyslny',
                style: TextStyle(color: AppColors.onSurfaceMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Zamknij', style: TextStyle(color: AppColors.primary)),
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

  _ColorTile({
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
        style: TextStyle(
          color: AppColors.onSurface,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        _hexColor(color),
        style: TextStyle(color: AppColors.onSurfaceMuted, fontSize: 12),
      ),
      trailing: Icon(
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

  _ColorDot({required this.color});

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

  _ColorSwatchButton({
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
            ? Icon(Icons.check_rounded, color: Colors.white, size: 22)
            : null,
      ),
    );
  }
}

String _hexColor(Color color) {
  final hex = color.toARGB32().toRadixString(16).padLeft(8, '0');
  return '#${hex.substring(2).toUpperCase()}';
}

class _FilterTile extends ConsumerWidget {
  final SubjectFilter filter;
  _FilterTile({required this.filter});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
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
          style: TextStyle(
              color: AppColors.onSurface,
              fontWeight: FontWeight.w500,
              fontSize: 14),
        ),
        subtitle: Text(
          '${filter.isHidden ? "Ukryty" : "Widoczny"} — Grupa: ${filter.groupId}',
          style: TextStyle(color: AppColors.onSurfaceMuted, fontSize: 12),
        ),
        trailing: IconButton(
          icon: Icon(Icons.delete_outline_rounded,
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

class _AddFilterDialog extends ConsumerStatefulWidget {
  const _AddFilterDialog();

  @override
  ConsumerState<_AddFilterDialog> createState() => _AddFilterDialogState();
}

class _AddFilterDialogState extends ConsumerState<_AddFilterDialog> {
  final _formKey = GlobalKey<FormState>();
  String? _selectedGroupId;
  String? _subject;
  bool _isHidden = true;
  bool _saving = false;

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final groups = ref.read(groupsProvider).valueOrNull ?? [];
    final groupId = groups.any((group) => group.groupId == _selectedGroupId)
        ? _selectedGroupId
        : groups.firstOrNull?.groupId;
    if (groupId == null || _subject == null) return;
    final filter = SubjectFilter(
      subject: _subject!,
      groupId: groupId,
      isHidden: _isHidden,
    );
    setState(() => _saving = true);
    try {
      await ref.read(subjectFiltersProvider.notifier).addFilter(filter);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Nie udało się zapisać filtra. Spróbuj ponownie.')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(groupsProvider);
    final groups = groupsAsync.valueOrNull ?? [];
    final groupId = groups.any((group) => group.groupId == _selectedGroupId)
        ? _selectedGroupId
        : groups.firstOrNull?.groupId;
    final subjectsAsync = groupId == null
        ? const AsyncData<List<String>>([])
        : ref.watch(filterSubjectsProvider(groupId));
    final subjects = subjectsAsync.valueOrNull ?? [];
    final canSave = groupId != null &&
        subjects.contains(_subject) &&
        !_saving &&
        !subjectsAsync.isLoading &&
        !subjectsAsync.hasError;

    return AlertDialog(
      scrollable: true,
      backgroundColor: AppColors.surface,
      title: Text('Dodaj filtr przedmiotu',
          style: TextStyle(color: AppColors.onSurface, fontSize: 16)),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (groups.isNotEmpty)
              DropdownButtonFormField<String>(
                key: ValueKey(groupId),
                initialValue: groupId,
                isExpanded: true,
                itemHeight: null,
                decoration: InputDecoration(labelText: 'Grupa'),
                dropdownColor: AppColors.surfaceVariant,
                items: groups
                    .map((g) => DropdownMenuItem(
                          value: g.groupId,
                          child: Text('${g.displayName} (${g.groupType.label})',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: AppColors.onSurface, fontSize: 13)),
                        ))
                    .toList(),
                onChanged: _saving
                    ? null
                    : (val) => setState(() {
                          _selectedGroupId = val;
                          _subject = null;
                        }),
                validator: (v) =>
                    v == null || v.isEmpty ? 'Wybierz grupę' : null,
              )
            else if (groupsAsync.isLoading)
              const CircularProgressIndicator()
            else
              Text(groupsAsync.hasError
                  ? 'Nie udało się odczytać grup.'
                  : 'Brak dodanych grup.'),
            if (groupId != null) ...[
              const SizedBox(height: 12),
              subjectsAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (_, __) => Column(
                  children: [
                    const Text('Nie udało się odczytać przedmiotów.'),
                    TextButton.icon(
                      onPressed: () =>
                          ref.invalidate(filterSubjectsProvider(groupId)),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Ponów'),
                    ),
                  ],
                ),
                data: (subjects) => subjects.isEmpty
                    ? const Text('Brak zapisanych przedmiotów dla tej grupy.')
                    : DropdownButtonFormField<String>(
                        key: ValueKey((groupId, subjects.join('\u001f'))),
                        initialValue:
                            subjects.contains(_subject) ? _subject : null,
                        isExpanded: true,
                        itemHeight: null,
                        menuMaxHeight: 320,
                        decoration:
                            const InputDecoration(labelText: 'Przedmiot'),
                        items: subjects
                            .map((subject) => DropdownMenuItem(
                                  value: subject,
                                  child: Text(subject,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis),
                                ))
                            .toList(),
                        onChanged: _saving
                            ? null
                            : (value) => setState(() => _subject = value),
                        validator: (value) =>
                            value == null ? 'Wybierz przedmiot' : null,
                      ),
              ),
            ],
            SizedBox(height: 12),
            Row(
              children: [
                Expanded(
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
                  onChanged:
                      _saving ? null : (v) => setState(() => _isHidden = v),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child:
              Text('Anuluj', style: TextStyle(color: AppColors.onSurfaceMuted)),
        ),
        ElevatedButton(
          onPressed: canSave ? _save : null,
          child: Text(_saving ? 'Zapisywanie…' : 'Zapisz'),
        ),
      ],
    );
  }
}
