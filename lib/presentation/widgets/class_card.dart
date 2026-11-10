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

  ClassCard({
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

  _NormalClassCard({
    required this.entry,
    required this.typeColor,
    required this.margin,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    const contentPadding = EdgeInsets.all(14);

    return Container(
      margin: margin,
      height:
          _cardHeight(context, extraLines: entry.studentGroups.isEmpty ? 0 : 1),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(color: typeColor, width: 4),
        ),
      ),
      child: Padding(
        padding: contentPadding,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ClassTitle(
              subject: entry.subject,
              classType: entry.classType,
              color: typeColor,
              compact: compact,
            ),
            if (entry.studentGroups.isNotEmpty) ...[
              const SizedBox(height: 4),
              _StudentGroups(value: entry.studentGroups),
            ],
            SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.access_time_rounded,
                  size: 14,
                  color: AppColors.onSurfaceMuted,
                ),
                SizedBox(width: 4),
                Expanded(
                  child: Text(
                    _formatTimeRange(entry.startTime, entry.endTime),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.onSurfaceMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            if (entry.lecturer.isNotEmpty) ...[
              SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    Icons.person_outline_rounded,
                    size: 14,
                    color: AppColors.onSurfaceMuted,
                  ),
                  SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      entry.lecturer,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.onSurfaceMuted,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (entry.room.isNotEmpty) ...[
              SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    Icons.room_outlined,
                    size: 14,
                    color: AppColors.onSurfaceMuted,
                  ),
                  SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      entry.room,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
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
  final EdgeInsetsGeometry margin;
  final bool compact;

  _MovedClassCard({
    required this.entry,
    required this.margin,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    const contentPadding = EdgeInsets.all(14);
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
      height:
          _cardHeight(context, extraLines: entry.studentGroups.isEmpty ? 0 : 1),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
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
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
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
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 6),
            Text(
              entry.subject,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.onSurfaceMuted,
                fontWeight: FontWeight.w600,
                fontSize: 15,
                decoration: TextDecoration.lineThrough,
                decorationColor: AppColors.onSurfaceMuted,
              ),
            ),
            if (entry.studentGroups.isNotEmpty) ...[
              const SizedBox(height: 4),
              _StudentGroups(value: entry.studentGroups),
            ],
            SizedBox(height: 4),
            Text(
              _formatTimeRange(entry.startTime, entry.endTime),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.onSurfaceMuted,
                fontSize: 13,
                decoration: TextDecoration.lineThrough,
              ),
            ),
            if (newDateText != null) ...[
              SizedBox(height: 8),
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
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
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

  _ClassTitle({
    required this.subject,
    required this.classType,
    required this.color,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final title = Text(
      subject,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: AppColors.onSurface,
        fontWeight: FontWeight.w600,
        fontSize: 15,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        title,
        SizedBox(height: 6),
        _TypeChip(classType: classType, color: color),
      ],
    );
  }
}

class BreakBlock extends StatelessWidget {
  final int minutes;

  BreakBlock({super.key, required this.minutes});

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
          SizedBox(width: 12),
          Icon(
            Icons.hourglass_empty_rounded,
            size: 13,
            color: AppColors.onSurfaceMuted.withValues(alpha: 0.6),
          ),
          SizedBox(width: 6),
          Flexible(
              child: Text(
            'Przerwa - $_durationLabel',
            style: TextStyle(
              color: AppColors.onSurfaceMuted.withValues(alpha: 0.7),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          )),
        ],
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String classType;
  final Color color;

  _TypeChip({
    required this.classType,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final background = Color.alphaBlend(
      color.withValues(alpha: 0.18),
      AppColors.surface,
    );
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        classType,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: AppColors.readableAccent(color, background),
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

typedef ScheduleEntryCallback = void Function(ScheduleEntry entry);

double _cardHeight(BuildContext context, {int extraLines = 0}) {
  double lineHeight(double size) {
    final painter = TextPainter(
      text: TextSpan(
          text: 'Ag',
          style: DefaultTextStyle.of(context)
              .style
              .merge(TextStyle(fontSize: size))),
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: Directionality.of(context),
      maxLines: 1,
    )..layout();
    final height = painter.height;
    painter.dispose();
    return height;
  }

  final title = lineHeight(15);
  final chip = lineHeight(11);
  final detail = lineHeight(13);
  final metadata = detail < 14 ? 14.0 : detail;
  final normal = title + 6 + chip + 6 + 8 + metadata * 3 + 8;
  final moved =
      (chip < 16 ? 16.0 : chip) + 6 + title + 4 + detail + 8 + detail * 2 + 12;
  return ((normal > moved ? normal : moved) + 28 + extraLines * (metadata + 4))
      .ceilToDouble();
}

class _StudentGroups extends StatelessWidget {
  const _StudentGroups({required this.value});
  final String value;
  @override
  Widget build(BuildContext context) => Tooltip(
        message: value,
        child: Row(children: [
          Icon(Icons.groups_outlined,
              size: 14, color: AppColors.onSurfaceMuted),
          const SizedBox(width: 4),
          Expanded(
              child: Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: AppColors.onSurface))),
        ]),
      );
}

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

  final sorted = [...entries]
    ..sort((a, b) => a.startTime.compareTo(b.startTime));
  for (final entry in sorted) {
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

  return LayoutBuilder(builder: (context, constraints) {
    final scale = MediaQuery.textScalerOf(context).scale(15) / 15;
    final columns = ((constraints.maxWidth - 32 + 8) / (148 * scale + 8))
        .floor()
        .clamp(1, 2);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          for (int start = 0;
              start < slot.entries.length;
              start += columns) ...[
            if (start > 0) SizedBox(height: 8),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (int i = start;
                  i < start + columns && i < slot.entries.length;
                  i++) ...[
                if (i > start) SizedBox(width: 8),
                Expanded(
                    child: _buildCompactEntryCard(slot.entries[i], onEntryTap,
                        onEntryLongPress, classTypeColors)),
              ],
              if (columns > 1 && start + 1 == slot.entries.length)
                const Expanded(child: SizedBox()),
            ]),
          ],
        ],
      ),
    );
  });
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
  final nextSlot = slots[index + 1];
  final currentActiveEnd = _latestActiveEnd(slots, index);
  final nextActiveStart = nextSlot.activeStartMinutes;

  if (currentActiveEnd != null) {
    if (nextSlot.hasMovedOnly) return null;
    if (nextActiveStart == null) return null;
    return nextActiveStart - currentActiveEnd;
  }

  return null;
}

int? _latestActiveEnd(List<_ScheduleSlot> slots, int index) {
  int? latest;
  for (int i = 0; i <= index; i++) {
    final activeEnd = slots[i].activeEndMinutes;
    if (activeEnd != null && (latest == null || activeEnd > latest)) {
      latest = activeEnd;
    }
  }
  return latest;
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
