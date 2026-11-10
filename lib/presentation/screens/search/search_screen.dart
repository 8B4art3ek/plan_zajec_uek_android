import 'package:flutter/material.dart';
import '../../widgets/failure_view.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/date_labels.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../data/datasources/lecturer_directory.dart';
import '../../../data/datasources/plan_directory.dart';
import '../../../data/repositories/schedule_repository_impl.dart';
import '../../../domain/entities/schedule_entry.dart';
import '../../providers/providers.dart';
import '../../providers/search_providers.dart';
import '../../widgets/app_scroll_view.dart';
import '../../widgets/class_card.dart';
import '../../widgets/event_editor_sheet.dart';
import '../../widgets/schedule_entry_details_sheet.dart';

Future<void> _openLink(BuildContext context, Uri uri) async {
  try {
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
  } catch (_) {
    // Not every phone has an application registered for mailto.
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nie można otworzyć linku.')));
  }
}

void openLecturer(BuildContext context, String name) => Navigator.of(context)
    .push(MaterialPageRoute(builder: (_) => LecturerScreen(name: name)));

void openRoom(BuildContext context, String room) =>
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => SearchScreen(initialTab: 2, initialQuery: room)));

class SearchScreen extends StatefulWidget {
  const SearchScreen(
      {super.key,
      this.initialTab = 0,
      this.initialQuery = '',
      this.category,
      this.selectLecturerPlan = false});
  final int initialTab;
  final String initialQuery;
  final Uri? category;
  final bool selectLecturerPlan;
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late final _query = TextEditingController(text: widget.initialQuery);
  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 3,
        initialIndex: widget.initialTab,
        child: Scaffold(
          appBar: AppBar(
              title: const Text('Wyszukaj'),
              bottom: const TabBar(isScrollable: true, tabs: [
                Tab(text: 'Zapisane zajęcia'),
                Tab(text: 'Wykładowcy'),
                Tab(text: 'Sale')
              ])),
          body: Column(children: [
            Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _query,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                      hintText: 'Szukaj',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _query.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Wyczyść',
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () => setState(_query.clear))),
                )),
            Expanded(
                child: TabBarView(children: [
              _SavedClasses(query: _query.text),
              _Catalogue(
                  kind: PlanKind.lecturer,
                  query: _query.text,
                  openPlanDirectly: widget.selectLecturerPlan,
                  category: widget.initialTab == 1 ? widget.category : null),
              _Catalogue(
                  kind: PlanKind.room,
                  query: _query.text,
                  category: widget.initialTab == 2 ? widget.category : null),
            ])),
          ]),
        ),
      );
}

class _SavedClasses extends ConsumerWidget {
  const _SavedClasses({required this.query});
  final String query;
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(savedScheduleProvider).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _LoadError(
              error: error,
              onRetry: () => ref.invalidate(savedScheduleProvider)),
          data: (entries) => _EntryList(entries: entries, query: query));
}

class _Catalogue extends ConsumerWidget {
  const _Catalogue(
      {required this.kind,
      required this.query,
      this.category,
      this.openPlanDirectly = false});
  final PlanKind kind;
  final String query;
  final Uri? category;
  final bool openPlanDirectly;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = planCatalogueProvider((kind, category));
    return ref.watch(provider).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) =>
              _LoadError(error: error, onRetry: () => ref.invalidate(provider)),
          data: (page) {
            final targets = page.targets
                .where((target) => matchesSearch(target.name, query))
                .toList();
            return RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(provider);
                await ref.read(provider.future);
              },
              child: AppScrollView(
                  child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                children: [
                  if (page.categories.isNotEmpty) ...[
                    const Text('Pozostałe kategorie'),
                    for (final category in page.categories.entries)
                      ListTile(
                        leading: const Icon(Icons.folder_outlined),
                        title: Text(category.value),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => SearchScreen(
                                    initialTab:
                                        kind == PlanKind.lecturer ? 1 : 2,
                                    initialQuery: query,
                                    selectLecturerPlan: openPlanDirectly,
                                    category: category.key))),
                      ),
                  ],
                  if (targets.isEmpty)
                    Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(page.categories.isEmpty
                            ? 'Brak wyników.'
                            : 'Brak wyników we wczytanej części katalogu.')),
                  for (final target in targets)
                    ListTile(
                      leading: Icon(kind == PlanKind.lecturer
                          ? Icons.person_outline
                          : Icons.room_outlined),
                      title: Text(target.name),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) =>
                              kind == PlanKind.lecturer && !openPlanDirectly
                                  ? LecturerScreen(
                                      name: target.name, target: target)
                                  : TargetScheduleScreen(target: target))),
                    ),
                ],
              )),
            );
          },
        );
  }
}

class TargetScheduleScreen extends ConsumerStatefulWidget {
  const TargetScheduleScreen({super.key, required this.target});
  final PlanTarget target;
  @override
  ConsumerState<TargetScheduleScreen> createState() =>
      _TargetScheduleScreenState();
}

class _TargetScheduleScreenState extends ConsumerState<TargetScheduleScreen> {
  String _query = '';
  int _period = 1;
  @override
  Widget build(BuildContext context) {
    final provider = targetScheduleProvider((widget.target, _period));
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.target.name,
              maxLines: 2, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
                tooltip: 'Odśwież plan',
                icon: const Icon(Icons.refresh_rounded),
                onPressed: () => ref.invalidate(provider))
          ]),
      body: Column(children: [
        Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              DropdownButtonFormField<int>(
                initialValue: _period,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Okres planu'),
                items: [
                  for (final period in ScheduleRepository.planPeriods)
                    DropdownMenuItem(
                        value: period, child: Text('Okres $period'))
                ],
                onChanged: (period) {
                  if (period != null && period != _period) {
                    setState(() => _period = period);
                  }
                },
              ),
              const SizedBox(height: 12),
              TextField(
                  onChanged: (value) => setState(() => _query = value),
                  decoration: const InputDecoration(
                      hintText: 'Szukaj zajęć',
                      prefixIcon: Icon(Icons.search_rounded))),
            ])),
        Expanded(
            child: ref.watch(provider).when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => _LoadError(
                    error: error, onRetry: () => ref.invalidate(provider)),
                data: (entries) =>
                    _EntryList(entries: entries, query: _query))),
      ]),
    );
  }
}

class _EntryList extends ConsumerWidget {
  const _EntryList({required this.entries, required this.query});
  final List<ScheduleEntry> entries;
  final String query;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(classTypeColorsProvider).value ?? {};
    final filtered = entries
        .where((entry) => matchesSearch(
              '${entry.subject} ${entry.lecturer} ${entry.room} ${entry.studentGroups} ${entry.classType} ${DateFormat('dd.MM.yyyy').format(entry.date)}',
              query,
            ))
        .toList()
      ..sort((a, b) {
        final date = a.date.compareTo(b.date);
        return date == 0 ? a.startTime.compareTo(b.startTime) : date;
      });
    return AppScrollView(
        child: ListView.builder(
      padding: const EdgeInsets.only(bottom: 32),
      itemCount: filtered.isEmpty ? 1 : filtered.length,
      itemBuilder: (context, index) {
        if (filtered.isEmpty) {
          return const Padding(
              padding: EdgeInsets.all(24), child: Text('Brak wyników.'));
        }
        final entry = filtered[index];
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (index == 0 || filtered[index - 1].date != entry.date)
            Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                child: Text(
                    '${DateFormat('dd.MM.yyyy').format(entry.date)} · ${polishWeekday(entry.date)}')),
          ClassCard(
              entry: entry,
              classTypeColors: colors,
              onTap: () => showScheduleEntryDetailsSheet(
                  context: context,
                  entry: entry,
                  onLecturerTap: entry.lecturer.isEmpty
                      ? null
                      : () => openLecturer(context, entry.lecturer),
                  onRoomTap: entry.room.isEmpty
                      ? null
                      : () => openRoom(context, entry.room),
                  onEdit: entry.groupId == 'user'
                      ? () => showUserEventSheetForEntry(
                            context: context,
                            ref: ref,
                            entry: entry,
                          )
                      : null)),
        ]);
      },
    ));
  }
}

class LecturerScreen extends ConsumerWidget {
  const LecturerScreen({super.key, required this.name, this.target});
  final String name;
  final PlanTarget? target;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = lecturerCardsProvider(name);
    return Scaffold(
      appBar: AppBar(
          title: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis)),
      body: AppScrollView(
          child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
            ListTile(
                leading: const Icon(Icons.calendar_month_outlined),
                title: const Text('Plan zajęć prowadzącego'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => target == null
                        ? SearchScreen(
                            initialTab: 1,
                            initialQuery: lecturerSearchName(name),
                            selectLecturerPlan: true)
                        : TargetScheduleScreen(target: target!)))),
            const Divider(),
            ...ref.watch(provider).when<List<Widget>>(
                loading: () => [
                      const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: CircularProgressIndicator()))
                    ],
                error: (_, __) => [
                      const Text('Nie udało się pobrać e-wizytówki.'),
                      TextButton.icon(
                          onPressed: () => ref.invalidate(provider),
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Spróbuj ponownie'))
                    ],
                data: (cards) => cards.isEmpty
                    ? [const Text('Nie znaleziono e-wizytówki.')]
                    : [for (final card in cards) _LecturerContact(card: card)]),
            TextButton.icon(
                onPressed: () =>
                    _openLink(context, LecturerDirectory.searchUri(name)),
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('Szukaj na e-Uczelni')),
          ])),
    );
  }
}

class _LecturerContact extends ConsumerWidget {
  const _LecturerContact({required this.card});
  final LecturerCard card;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = lecturerContactProvider(card);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ListTile(
          title: Text(card.name),
          leading: const Icon(Icons.badge_outlined),
          trailing: const Icon(Icons.open_in_new_rounded),
          onTap: () => _openLink(context, card.uri)),
      ...ref.watch(provider).when<List<Widget>>(
          loading: () => [const LinearProgressIndicator()],
          error: (_, __) => [
                TextButton.icon(
                    onPressed: () => ref.invalidate(provider),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Ponów pobieranie kontaktu'))
              ],
          data: (contact) => [
                for (final email in contact.emails)
                  ListTile(
                      leading: const Icon(Icons.mail_outline),
                      title: Text(email),
                      onTap: () => _openLink(
                          context, Uri(scheme: 'mailto', path: email)),
                      trailing: IconButton(
                          tooltip: 'Kopiuj e-mail',
                          icon: const Icon(Icons.copy_rounded),
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: email));
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('Skopiowano e-mail.')));
                            }
                          })),
                if (contact.emails.isEmpty)
                  const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Brak opublikowanego e-maila.')),
              ]),
    ]);
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) =>
      FailureView(error: error, onRetry: onRetry);
}
