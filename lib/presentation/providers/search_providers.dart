import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/lecturer_directory.dart';
import '../../data/datasources/plan_directory.dart';
import '../../domain/entities/schedule_entry.dart';
import 'providers.dart';

final planDirectoryProvider = Provider((ref) => PlanDirectory(
      ref.watch(remoteDatasourceProvider),
      ref.watch(authServiceProvider),
    ));

final planCatalogueProvider = FutureProvider.autoDispose
    .family<PlanDirectoryPage, (PlanKind, Uri?)>((ref, key) async {
  var cancelled = false;
  ref.onDispose(() => cancelled = true);
  final result = await ref
      .watch(planDirectoryProvider)
      .catalogue(key.$1, page: key.$2, cancelled: () => cancelled);
  if (!cancelled && result.categories.isEmpty) {
    final link = ref.keepAlive();
    final timer = Timer(const Duration(minutes: 5), link.close);
    ref.onDispose(timer.cancel);
  }
  return result;
});

final targetScheduleProvider = FutureProvider.autoDispose
    .family<List<ScheduleEntry>, (PlanTarget, int)>((ref, request) {
  return ref.watch(planDirectoryProvider).schedule(request.$1, request.$2);
});

final savedScheduleProvider =
    FutureProvider.autoDispose<List<ScheduleEntry>>((ref) async {
  ref.watch(groupsProvider);
  ref.watch(refreshInfoProvider);
  ref.watch(userEventsProvider);
  final repo = ref.watch(scheduleRepositoryProvider);
  final entries = await repo.getSavedEntries();
  final events = await repo.getUserEvents();
  return [
    ...entries,
    for (final event in events)
      ScheduleEntry(
        id: 'event_${event.id}',
        subject: event.title,
        classType: event.eventType,
        lecturer: '',
        room: event.room ?? '',
        date: event.date,
        startTime: event.startTime,
        endTime: event.endTime,
        weekday: '',
        durationHours: 0,
        groupId: 'user',
        groupType: GroupType.dean,
      )
  ];
});

final lecturerDirectoryProvider = Provider((ref) {
  final directory = LecturerDirectory();
  ref.onDispose(directory.close);
  return directory;
});

final lecturerCardsProvider = FutureProvider.autoDispose
    .family<List<LecturerCard>, String>(
        (ref, name) => ref.watch(lecturerDirectoryProvider).search(name));

final lecturerContactProvider = FutureProvider.autoDispose
    .family<LecturerContact, LecturerCard>(
        (ref, card) => ref.watch(lecturerDirectoryProvider).contact(card));
