// lib/presentation/screens/groups/groups_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/group.dart';
import '../../../domain/entities/schedule_entry.dart';
import '../../providers/providers.dart';
import 'usos_import_screen.dart';

class GroupsScreen extends ConsumerWidget {
  const GroupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(groupsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Grupy')),
      body: groupsAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(
            child: Text(e.toString(),
                style: const TextStyle(color: AppColors.error))),
        data: (groups) {
          final deanGroups =
              groups.where((g) => g.groupType == GroupType.dean).toList();
          final langGroups =
              groups.where((g) => g.groupType == GroupType.language).toList();
          final peGroups =
              groups.where((g) => g.groupType == GroupType.pe).toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _ImportUsosButton(
                onTap: () => _openUsosImport(context, ref),
              ),
              const SizedBox(height: 20),
              const _SectionHeader(
                title: 'Grupy dziekanskie',
                icon: Icons.school_rounded,
                color: AppColors.primary,
              ),
              const SizedBox(height: 8),
              ...deanGroups.map((g) => _GroupTile(group: g)),
              _AddGroupButton(
                label: 'Dodaj grupe dziekanska',
                onTap: () => _showAddGroupDialog(
                    context, ref, GroupType.dean, deanGroups.length),
              ),
              const SizedBox(height: 24),
              const _SectionHeader(
                title: 'Grupy jezykowe (max 2)',
                icon: Icons.language_rounded,
                color: AppColors.lektorat,
              ),
              const SizedBox(height: 8),
              ...langGroups.map((g) => _GroupTile(group: g)),
              if (langGroups.length < 2)
                _AddGroupButton(
                  label: 'Dodaj grupe jezykowa',
                  onTap: () => _showAddGroupDialog(
                      context, ref, GroupType.language, langGroups.length),
                ),
              if (langGroups.length >= 2)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    'Osiagnięto limit 2 grup jezykowych',
                    style: TextStyle(
                        color: AppColors.onSurfaceMuted, fontSize: 13),
                  ),
                ),
              const SizedBox(height: 24),
              const _SectionHeader(
                title: 'Grupy WF',
                icon: Icons.fitness_center_rounded,
                color: AppColors.wf,
              ),
              const SizedBox(height: 8),
              ...peGroups.map((g) => _GroupTile(group: g)),
              _AddGroupButton(
                label: 'Dodaj grupe WF',
                onTap: () => _showAddGroupDialog(
                    context, ref, GroupType.pe, peGroups.length),
              ),
              const SizedBox(height: 32),
              const _InfoCard(),
            ],
          );
        },
      ),
    );
  }

  void _showAddGroupDialog(
      BuildContext context, WidgetRef ref, GroupType type, int currentCount) {
    showDialog(
      context: context,
      builder: (_) => _AddGroupDialog(type: type, widgetRef: ref),
    );
  }

  Future<void> _openUsosImport(BuildContext context, WidgetRef ref) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const UsosImportScreen()),
    );
    if (changed == true) {
      ref.invalidate(groupsProvider);
      ref.invalidate(todayScheduleProvider);
      ref.invalidate(refreshInfoProvider);
    }
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;

  const _SectionHeader({
    required this.title,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            color: AppColors.onSurface,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _GroupTile extends ConsumerWidget {
  final Group group;

  const _GroupTile({required this.group});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = _colorForType(group.groupType);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Text(
              group.groupType.label[0],
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ),
        ),
        title: Text(
          group.name ?? 'ID: ${group.groupId}',
          style: const TextStyle(
            color: AppColors.onSurface,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        subtitle: Text(
          group.name == null
              ? group.groupType.label
              : '${group.groupType.label} - ID: ${group.groupId}',
          style: const TextStyle(color: AppColors.onSurfaceMuted, fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: group.isEnabled,
              onChanged: (val) {
                ref
                    .read(groupsProvider.notifier)
                    .updateGroup(group.copyWith(isEnabled: val));
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded,
                  color: AppColors.error, size: 20),
              onPressed: () => _confirmDelete(context, ref),
            ),
          ],
        ),
      ),
    );
  }

  Color _colorForType(GroupType type) {
    switch (type) {
      case GroupType.dean:
        return AppColors.primary;
      case GroupType.language:
        return AppColors.lektorat;
      case GroupType.pe:
        return AppColors.wf;
    }
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Usun grupe',
            style: TextStyle(color: AppColors.onSurface)),
        content: Text(
          'Czy na pewno chcesz usunac grupe ${group.groupId}?\nWszystkie zajecia tej grupy zostana usuniete.',
          style: const TextStyle(color: AppColors.onSurfaceMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Anuluj',
                style: TextStyle(color: AppColors.onSurfaceMuted)),
          ),
          TextButton(
            onPressed: () {
              ref.read(groupsProvider.notifier).deleteGroup(group.groupId);
              Navigator.pop(context);
            },
            child: const Text('Usun', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}

class _ImportUsosButton extends StatelessWidget {
  final VoidCallback onTap;

  const _ImportUsosButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.28)),
        ),
        child: const Row(
          children: [
            Icon(Icons.cloud_download_rounded, color: AppColors.primary),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Import z USOS',
                    style: TextStyle(
                      color: AppColors.onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Skanuj grupy dziekanskie i jezykowe',
                    style: TextStyle(
                      color: AppColors.onSurfaceMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: AppColors.onSurfaceMuted,
            ),
          ],
        ),
      ),
    );
  }
}

class _AddGroupButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _AddGroupButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.3),
            width: 1,
            style: BorderStyle.solid,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.add_circle_outline_rounded,
                color: AppColors.primary.withValues(alpha: 0.8), size: 20),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                color: AppColors.primary.withValues(alpha: 0.9),
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddGroupDialog extends StatefulWidget {
  final GroupType type;
  final WidgetRef widgetRef;

  const _AddGroupDialog({required this.type, required this.widgetRef});

  @override
  State<_AddGroupDialog> createState() => _AddGroupDialogState();
}

class _AddGroupDialogState extends State<_AddGroupDialog> {
  final _formKey = GlobalKey<FormState>();
  final _idCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _idCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isSaving = true);

    final group = Group(
      groupId: _idCtrl.text.trim(),
      groupType: widget.type,
      name: _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
      isEnabled: true,
    );

    try {
      await widget.widgetRef.read(groupsProvider.notifier).addGroup(group);
      // Immediately try to fetch
      await widget.widgetRef
          .read(scheduleRepositoryProvider)
          .refreshGroup(group);
      widget.widgetRef.invalidate(todayScheduleProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Blad pobierania planu: $e'),
            backgroundColor: AppColors.error,
          ),
        );
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(
        'Dodaj grupe ${widget.type.label.toLowerCase()}',
        style: const TextStyle(color: AppColors.onSurface, fontSize: 17),
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _idCtrl,
              decoration: const InputDecoration(
                labelText: 'ID grupy',
                hintText: 'np. 239641',
              ),
              keyboardType: TextInputType.number,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Podaj ID grupy';
                if (int.tryParse(v.trim()) == null) {
                  return 'ID musi byc liczba';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Nazwa (opcjonalnie)',
                hintText: 'np. Gr. 3',
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'ID znajdziesz w adresie URL planu zajec:\nhttps://planzajec.uek.krakow.pl/index.php?typ=G&id=TUTAJ&okres=2',
                style: TextStyle(color: AppColors.onSurfaceMuted, fontSize: 11),
              ),
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
          onPressed: _isSaving ? null : _add,
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('Dodaj'),
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline_rounded,
                  color: AppColors.primary, size: 16),
              SizedBox(width: 8),
              Text('Jak znalezc ID grupy?',
                  style: TextStyle(
                      color: AppColors.onSurface,
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
            ],
          ),
          SizedBox(height: 8),
          Text(
            '1. Wejdz na planzajec.uek.krakow.pl\n'
            '2. Zaloguj sie danymi USOS\n'
            '3. Wybierz swoja grupe\n'
            '4. Skopiuj numer z parametru "id=" w adresie URL',
            style: TextStyle(
                color: AppColors.onSurfaceMuted, fontSize: 12, height: 1.6),
          ),
        ],
      ),
    );
  }
}
