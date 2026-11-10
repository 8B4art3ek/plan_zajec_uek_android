import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/schedule_entry.dart';

Future<void> showScheduleEntryDetailsSheet({
  required BuildContext context,
  required ScheduleEntry entry,
  VoidCallback? onEdit,
  VoidCallback? onLecturerTap,
  VoidCallback? onRoomTap,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: SingleChildScrollView(
            child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.onSurfaceMuted.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            SizedBox(height: 20),
            Text(
              entry.subject,
              style: TextStyle(
                color: AppColors.onSurface,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 8),
            if (entry.isMoved) ...[
              _DetailRow(
                icon: Icons.swap_horiz_rounded,
                label: 'Status',
                value: 'Zajęcia przeniesione',
                valueColor: AppColors.warning,
              ),
              SizedBox(height: 12),
            ],
            _DetailRow(
              icon: Icons.school_outlined,
              label: 'Typ zajęć',
              value: entry.classType.isEmpty ? 'Brak danych' : entry.classType,
            ),
            SizedBox(height: 12),
            _DetailRow(
              icon: Icons.access_time_rounded,
              label: 'Data i godzina',
              value:
                  '${entry.date.day.toString().padLeft(2, '0')}.${entry.date.month.toString().padLeft(2, '0')}.${entry.date.year}\n${entry.startTime} - ${entry.endTime}',
            ),
            if (entry.studentGroups.isNotEmpty) ...[
              const SizedBox(height: 12),
              _DetailRow(
                  icon: Icons.groups_outlined,
                  label: 'Grupa',
                  value: entry.studentGroups),
            ],
            if (entry.lecturer.isNotEmpty) ...[
              SizedBox(height: 12),
              _DetailRow(
                icon: Icons.person_outline_rounded,
                label: 'Prowadzący',
                value: entry.lecturer,
                onTap: onLecturerTap == null
                    ? null
                    : () {
                        Navigator.of(sheetContext).pop();
                        onLecturerTap();
                      },
              ),
            ],
            if (entry.room.isNotEmpty) ...[
              SizedBox(height: 12),
              _DetailRow(
                icon: Icons.room_outlined,
                label: 'Sala',
                value: entry.room,
                onTap: onRoomTap == null
                    ? null
                    : () {
                        Navigator.of(sheetContext).pop();
                        onRoomTap();
                      },
              ),
            ],
            if (entry.isMoved && entry.newDate != null) ...[
              SizedBox(height: 12),
              _DetailRow(
                icon: Icons.event_repeat_rounded,
                label: 'Nowy termin',
                value:
                    '${entry.newDate!.day.toString().padLeft(2, '0')}.${entry.newDate!.month.toString().padLeft(2, '0')}.${entry.newDate!.year} ${entry.newStartTime ?? ''}${entry.newEndTime == null ? '' : ' - ${entry.newEndTime}'}',
              ),
            ],
            if (onEdit != null) ...[
              SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    onEdit();
                  },
                  icon: Icon(Icons.edit_outlined),
                  label: Text('Edytuj wydarzenie'),
                ),
              ),
            ],
          ],
        )),
      ),
    ),
  );
}

class _DetailRow extends StatelessWidget {
  _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 19, color: AppColors.onSurfaceMuted),
        SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: AppColors.onSurfaceMuted,
                  fontSize: 12,
                ),
              ),
              SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  color: valueColor ?? AppColors.onSurface,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (onTap != null) const Icon(Icons.chevron_right_rounded),
      ],
    );
    return onTap == null
        ? row
        : InkWell(
            onTap: onTap,
            child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6), child: row),
          );
  }
}
