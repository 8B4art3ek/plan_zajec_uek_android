import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/lecturer_directory.dart';
import '../../data/datasources/plan_directory.dart';
import '../../domain/entities/schedule_entry.dart';
import 'providers.dart';

const _planCacheDuration = Duration(minutes: 5);

final planDirectoryProvider = Provider((ref) {
  ref.watch(credentialsProvider.future);
  return PlanDirectory(
    ref.watch(remoteDatasourceProvider),
    ref.watch(authServiceProvider),
  );
});

final planCatalogueProvider = StreamProvider.autoDispose
    .family<PlanDirectoryPage, (PlanKind, Uri?)>((ref, key) async* {
  var cancelled = false;
  ref.onDispose(() => cancelled = true);
  await for (final result in ref
      .watch(planDirectoryProvider)
      .catalogue(key.$1, page: key.$2, cancelled: () => cancelled)) {
    if (cancelled) return;
    if (!result.loadingMore && result.categories.isEmpty) {
      final link = ref.keepAlive();
      final timer = Timer(_planCacheDuration, link.close);
      ref.onDispose(timer.cancel);
    }
    yield result;
  }
});

final targetScheduleProvider = FutureProvider.autoDispose
    .family<List<ScheduleEntry>, (PlanTarget, int)>((ref, request) async {
  var disposed = false;
  ref.onDispose(() => disposed = true);
  final entries =
      await ref.watch(planDirectoryProvider).schedule(request.$1, request.$2);
  if (!disposed) {
    final link = ref.keepAlive();
    final timer = Timer(_planCacheDuration, link.close);
    ref.onDispose(timer.cancel);
  }
  return entries;
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
