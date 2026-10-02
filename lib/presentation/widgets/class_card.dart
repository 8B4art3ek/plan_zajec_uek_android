// lib/presentation/widgets/class_card.dart

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/schedule_entry.dart';

class ClassCard extends StatelessWidget {
  final ScheduleEntry entry;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry margin;
  final bool compact;
  final Map<String, Color> classTypeColors;

  const ClassCard({
    super.key,
    required this.entry,
    this.onTap,
    this.onLongPress,
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    this.compact = false,
    this.classTypeColors = const {},
  });

  @override
  Widget build(BuildContext context) {
    final typeColor =
        AppColors.classTypeColor(entry.classType, classTypeColors);

    final card = entry.isMoved
        ? _MovedClassCard(
            entry: entry,
            typeColor: typeColor,
            margin: margin,
            compact: compact,
          )
        : _NormalClassCard(
            entry: entry,
            typeColor: typeColor,
            margin: margin,
            compact: compact,
          );

    if (onTap == null && onLongPress == null) return card;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: card,
    );
  }
}

class _NormalClassCard extends StatelessWidget {
  final ScheduleEntry entry;
  final Color typeColor;
  final EdgeInsetsGeometry margin;
  final bool compact;

  const _NormalClassCard({
    required this.entry,
    required this.typeColor,
    required this.margin,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final contentPadding =
        compact ? const EdgeInsets.all(12) : const EdgeInsets.all(14);

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border(
          left: BorderSide(color: typeColor, width: 4),
        ),
      ),
      child: Padding(
        padding: contentPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ClassTitle(
              subject: entry.subject,
              classType: entry.classType,
              color: typeColor,
              compact: compact,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  Icons.access_time_rounded,
                  size: 14,
                  color: AppColors.onSurfaceMuted,
                ),
                const SizedBox(width: 4),
                Text(
                  _formatTimeRange(entry.startTime, entry.endTime),
                  style: const TextStyle(
                    color: AppColors.onSurfaceMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            if (entry.lecturer.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(
                    Icons.person_outline_rounded,
                    size: 14,
                    color: AppColors.onSurfaceMuted,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      entry.lecturer,
                      style: const TextStyle(
                        color: AppColors.onSurfaceMuted,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (entry.room.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(
                    Icons.room_outlined,
                    size: 14,
                    color: AppColors.onSurfaceMuted,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      entry.room,
                      softWrap: true,
                      style: const TextStyle(
                        color: AppColors.onSurfaceMuted,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MovedClassCard extends StatelessWidget {
  final ScheduleEntry entry;
  final Color typeColor;
  final EdgeInsetsGeometry margin;
  final bool compact;

  const _MovedClassCard({
    required this.entry,
    required this.typeColor,
    required this.margin,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final contentPadding =
        compact ? const EdgeInsets.all(12) : const EdgeInsets.all(14);
    final newDate = entry.newDate;
    final newStart = entry.newStartTime;
    final newEnd = entry.newEndTime;
    final newDateText = newDate == null
        ? null
        : '${newDate.day.toString().padLeft(2, '0')}.${newDate.month.toString().padLeft(2, '0')}';
    final newTimeText =
        newStart == null ? null : _formatTimeRange(newStart, newEnd);

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border(
          left: BorderSide(
            color: AppColors.warning.withValues(alpha: 0.6),
            width: 4,
          ),
        ),
      ),
      child: Padding(
        padding: contentPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.swap_horiz_rounded,
                  size: 16,
                  color: AppColors.warning,
                ),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'PRZENIESIONE',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.warning,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              entry.subject,
              style: TextStyle(
                color: AppColors.onSurfaceMuted,
                fontWeight: FontWeight.w600,
                fontSize: compact ? 14 : 15,
                decoration: TextDecoration.lineThrough,
                decorationColor: AppColors.onSurfaceMuted,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _formatTimeRange(entry.startTime, entry.endTime),
              style: TextStyle(
                color: AppColors.onSurfaceMuted,
                fontSize: compact ? 12 : 13,
                decoration: TextDecoration.lineThrough,
              ),
            ),
            if (newDateText != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Przeniesione na: $newDateText${newTimeText == null ? '' : ' $newTimeText'}',
                  style: const TextStyle(
                    color: AppColors.warning,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ClassTitle extends StatelessWidget {
  final String subject;
  final String classType;
  final Color color;
  final bool compact;

  const _ClassTitle({
    required this.subject,
    required this.classType,
    required this.color,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final title = Text(
      subject,
      softWrap: true,
      style: TextStyle(
        color: AppColors.onSurface,
        fontWeight: FontWeight.w600,
        fontSize: compact ? 14 : 15,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        title,
        SizedBox(height: compact ? 5 : 6),
        _TypeChip(classType: classType, color: color, compact: compact),
      ],
    );
  }
}

class BreakBlock extends StatelessWidget {
  final int minutes;

  const BreakBlock({super.key, required this.minutes});

  String get _durationLabel {
    if (minutes > 59) {
      final hours = minutes ~/ 60;
      final restMinutes = minutes % 60;
      if (restMinutes == 0) return '$hours h';
      return '$hours h $restMinutes min';
    }
    return '$minutes min';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 2),
      child: Row(
        children: [
          Container(
            width: 2,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.onSurfaceMuted.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          const SizedBox(width: 12),
          Icon(
            Icons.hourglass_empty_rounded,
            size: 13,
            color: AppColors.onSurfaceMuted.withValues(alpha: 0.6),
          ),
          const SizedBox(width: 6),
          Text(
            'Przerwa - $_durationLabel',
            style: TextStyle(
              color: AppColors.onSurfaceMuted.withValues(alpha: 0.7),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String classType;
  final Color color;
  final bool compact;

  const _TypeChip({
    required this.classType,
    required this.color,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        classType,
        style: TextStyle(
          color: color,
          fontSize: compact ? 10 : 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

typedef ScheduleEntryCallback = void Function(ScheduleEntry entry);

List<Widget> buildScheduleWidgets(
  List<ScheduleEntry> entries, {
  ScheduleEntryCallback? onEntryTap,
  ScheduleEntryCallback? onEntryLongPress,
  Map<String, Color> classTypeColors = const {},
}) {
  final widgets = <Widget>[];
  final slots = _buildScheduleSlots(entries);

  for (int i = 0; i < slots.length; i++) {
    final slot = slots[i];
    widgets.add(
      _buildSlotWidget(
        slot,
        onEntryTap,
        onEntryLongPress,
        classTypeColors,
      ),
    );

    if (i < slots.length - 1) {
      final gap = _breakAfterSlot(slots, i);
      if (gap != null && _shouldShowBreak(gap)) {
        widgets.add(BreakBlock(minutes: gap));
      }
    }
  }

  return widgets;
}

String _formatTimeRange(String startTime, String? endTime) {
  if (endTime == null || endTime.isEmpty) return startTime;
  if (startTime.isEmpty) return endTime;
  return '$startTime - $endTime';
}

bool _shouldShowBreak(int minutes) => minutes > 0 && minutes != 15;

List<_ScheduleSlot> _buildScheduleSlots(List<ScheduleEntry> entries) {
  final slots = <_ScheduleSlot>[];

  for (final entry in entries) {
    if (slots.isNotEmpty && slots.last.startTime == entry.startTime) {
      slots.last.entries.add(entry);
    } else {
      slots.add(_ScheduleSlot(entry.startTime, [entry]));
    }
  }

  return slots;
}

Widget _buildSlotWidget(
  _ScheduleSlot slot,
  ScheduleEntryCallback? onEntryTap,
  ScheduleEntryCallback? onEntryLongPress,
  Map<String, Color> classTypeColors,
) {
  if (slot.entries.length == 1) {
    final entry = slot.entries.first;
    return ClassCard(
      entry: entry,
      classTypeColors: classTypeColors,
      onTap: onEntryTap == null ? null : () => onEntryTap(entry),
      onLongPress:
          onEntryLongPress == null ? null : () => onEntryLongPress(entry),
    );
  }

  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < slot.entries.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: _buildCompactEntryCard(
                slot.entries[i],
                onEntryTap,
                onEntryLongPress,
                classTypeColors,
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

Widget _buildCompactEntryCard(
  ScheduleEntry entry,
  ScheduleEntryCallback? onEntryTap,
  ScheduleEntryCallback? onEntryLongPress,
  Map<String, Color> classTypeColors,
) {
  return ClassCard(
    entry: entry,
    margin: EdgeInsets.zero,
    compact: true,
    classTypeColors: classTypeColors,
    onTap: onEntryTap == null ? null : () => onEntryTap(entry),
    onLongPress:
        onEntryLongPress == null ? null : () => onEntryLongPress(entry),
  );
}

int? _breakAfterSlot(List<_ScheduleSlot> slots, int index) {
  final slot = slots[index];
  final nextSlot = slots[index + 1];
  final currentActiveEnd = slot.activeEndMinutes;
  final nextActiveStart = nextSlot.activeStartMinutes;

  if (currentActiveEnd != null) {
    if (nextSlot.hasMovedOnly) return null;
    if (nextActiveStart == null) return null;
    return nextActiveStart - currentActiveEnd;
  }

  if (!slot.hasMovedOnly || !nextSlot.hasActive) return null;

  final previousEnd = _previousActiveEnd(slots, index);
  final nextStart = nextSlot.activeStartMinutes;
  if (previousEnd == null || nextStart == null) return null;

  return nextStart - previousEnd;
}

int? _previousActiveEnd(List<_ScheduleSlot> slots, int index) {
  for (int i = index - 1; i >= 0; i--) {
    final activeEnd = slots[i].activeEndMinutes;
    if (activeEnd != null) return activeEnd;
  }
  return null;
}

int? _timeToMinutes(String time) {
  final parts = time.split(':');
  if (parts.length != 2) return null;

  final hours = int.tryParse(parts[0]);
  final minutes = int.tryParse(parts[1]);
  if (hours == null || minutes == null) return null;
  if (hours < 0 || hours > 23 || minutes < 0 || minutes > 59) return null;

  return hours * 60 + minutes;
}

class _ScheduleSlot {
  final String startTime;
  final List<ScheduleEntry> entries;

  _ScheduleSlot(this.startTime, this.entries);

  bool get hasActive => entries.any((entry) => !entry.isMoved);

  bool get hasMovedOnly => entries.every((entry) => entry.isMoved);

  int? get activeStartMinutes {
    final starts = entries
        .where((entry) => !entry.isMoved)
        .map((entry) => _timeToMinutes(entry.startTime))
        .whereType<int>();
    if (starts.isEmpty) return null;
    return starts.reduce((a, b) => a < b ? a : b);
  }

  int? get activeEndMinutes {
    final ends = entries
        .where((entry) => !entry.isMoved)
        .map((entry) => _timeToMinutes(entry.endTime))
        .whereType<int>();
    if (ends.isEmpty) return null;
    return ends.reduce((a, b) => a > b ? a : b);
  }
}
