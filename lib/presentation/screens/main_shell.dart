// lib/presentation/screens/main_shell.dart

import 'dart:async';
import '../../core/app_identity.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';
import 'attendance/attendance_screen.dart';
import 'travel/travel_screen.dart';
import 'home/home_screen.dart';
import 'groups/groups_screen.dart';
import 'settings/settings_screen.dart';
import '../providers/app_update_provider.dart';
import 'settings/app_updates_screen.dart';
import 'groups/usos_import_screen.dart';
import '../providers/startup_provider.dart';
import '../widgets/startup_alerts.dart';

final _currentTabProvider = StateProvider<int>((ref) => 0);
const _navigationItems = [
  ('Plan', Icons.calendar_today_outlined, Icons.calendar_today_rounded),
  ('Obecności', Icons.fact_check_outlined, Icons.fact_check_rounded),
  ('Dojazdy', Icons.route_outlined, Icons.route_rounded),
  ('Więcej', Icons.grid_view_outlined, Icons.grid_view_rounded),
];

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell>
    with WidgetsBindingObserver {
  bool _starting = false;
  DateTime? _lastCheck;
  Timer? _retryTimer;
  DateTime? _retryAt;

  Future<void> _scheduleAutomaticRefresh() async {
    try {
      final repo = ref.read(scheduleRepositoryProvider);
      final minutes = await repo.automaticRefreshMinutes();
      final due = minutes == 0 ? null : await repo.automaticRefreshDueAt();
      if (mounted) {
        _scheduleRetry(due != null && due.isBefore(DateTime.now())
            ? DateTime.now().add(Duration(minutes: minutes))
            : due);
      }
    } catch (_) {
      // A temporary settings read failure must not escape a timer callback.
    }
  }

  void _scheduleRetry(DateTime? date) {
    if (_retryAt == date) return;
    _retryTimer?.cancel();
    _retryAt = date;
    if (date == null) return;
    final delay = date.difference(DateTime.now());
    _retryTimer = Timer(delay.isNegative ? Duration.zero : delay, () {
      _retryAt = null;
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        unawaited(_startup());
      }
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => unawaited(_startup(firstOpen: true)));
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        (_lastCheck == null ||
            DateTime.now().difference(_lastCheck!) >=
                const Duration(minutes: 5))) {
      unawaited(_startup());
    }
  }

  bool get _canShow => mounted && ModalRoute.of(context)?.isCurrent != false;

  Future<void> _startup({bool firstOpen = false}) async {
    if (_starting || !_canShow) return;
    _starting = true;
    _lastCheck = DateTime.now();
    try {
      if (ref.read(pendingGroupSetupProvider)) {
        ref.read(pendingGroupSetupProvider.notifier).state = false;
        final choice = await showGroupSetupChoice(context);
        if (!mounted) return;
        if (choice == GroupSetupChoice.usos) {
          await Navigator.of(context).push<bool>(
              MaterialPageRoute(builder: (_) => UsosImportScreen()));
        } else if (choice == GroupSetupChoice.manual) {
          await Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => GroupsScreen()));
        }
        if (!_canShow) return;
      }
      if (firstOpen) {
        final service = ref.read(startupServiceProvider);
        try {
          final release = await service.pendingRelease();
          if (!mounted) return;
          if (!_canShow) return;
          if (release != null && await showReleaseNews(context, release)) {
            await service.acknowledgeRelease(release);
          }
        } catch (_) {
          // Installed-app metadata must not prevent importing or loading a plan.
        }
      }
      if (!_canShow) return;
      final repository = ref.read(scheduleRepositoryProvider);
      final groups = await repository.getGroups();
      final minutes = await repository.automaticRefreshMinutes();
      final nextAttempt = await repository.automaticRefreshDueAt();
      if (!_canShow) return;
      if (minutes != 0 &&
          groups.any((group) => group.isEnabled) &&
          (nextAttempt == null || !DateTime.now().isBefore(nextAttempt)) &&
          !ref.read(isRefreshingProvider)) {
        ref.read(isRefreshingProvider.notifier).state = true;
        try {
          await repository.refreshAllGroups();
        } catch (_) {
          // Previously detected changes remain available even when offline.
        } finally {
          if (mounted) {
            ref.read(isRefreshingProvider.notifier).state = false;
            ref.invalidate(todayScheduleProvider);
            ref.invalidate(refreshInfoProvider);
          }
        }
      }
      final changes = await repository.getPendingScheduleChanges();
      if (!mounted) return;
      if (!_canShow) return;
      if (changes.isNotEmpty && await showScheduleChanges(context, changes)) {
        await repository.acknowledgeScheduleChanges([
          for (final change in changes)
            if (change.id != null) change.id!,
        ]);
      }
      if (firstOpen && _canShow) await _checkForUpdate();
    } catch (_) {
      if (mounted && _canShow) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Nie udało się sprawdzić zmian w planie. Spróbuj odświeżyć plan.')));
      }
    } finally {
      _starting = false;
      if (mounted) await _scheduleAutomaticRefresh();
    }
  }

  Future<void> _checkForUpdate() async {
    final updates = ref.read(appUpdateProvider);
    if (updates.checked || updates.busy) return;
    await updates.check();
    if (!mounted) return;
    if (!_canShow || !updates.available) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Dostępna aktualizacja: ${updates.release!.version}'),
      action: SnackBarAction(
          label: 'Zobacz',
          onPressed: () {
            Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AppUpdatesScreen()));
          }),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final currentTab = ref.watch(_currentTabProvider);
    ref.listen(refreshInfoProvider, (_, next) {
      if (next.hasValue) unawaited(_scheduleAutomaticRefresh());
    });
    ref.listen(refreshMinutesProvider, (_, next) {
      if (next.hasValue) unawaited(_scheduleAutomaticRefresh());
    });
    ref.watch(appThemeProvider);
    final tabs = [
      HomeScreen(),
      AttendanceScreen(),
      const TravelScreen(),
      SettingsScreen(),
    ];

    final wide = MediaQuery.sizeOf(context).width >= 840 &&
        MediaQuery.textScalerOf(context).scale(1) <= 1.6;
    void select(int index) =>
        ref.read(_currentTabProvider.notifier).state = index;
    return PopScope(
      canPop: currentTab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) select(0);
      },
      child: Scaffold(
        body: Row(children: [
          if (wide)
            SafeArea(
                child: NavigationRail(
              selectedIndex: currentTab,
              onDestinationSelected: select,
              labelType: NavigationRailLabelType.none,
              leading: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Tooltip(
                      message: appName,
                      child: Image.asset(appIconAsset, width: 36, height: 36))),
              destinations: [
                for (final item in _navigationItems)
                  NavigationRailDestination(
                      icon: Icon(item.$2),
                      selectedIcon: Icon(item.$3),
                      label: Text(item.$1))
              ],
            )),
          if (wide) const VerticalDivider(width: 1),
          Expanded(
              key: const ValueKey('main-content'),
              child: IndexedStack(index: currentTab, children: tabs)),
        ]),
        bottomNavigationBar: wide
            ? null
            : NavigationBar(
                selectedIndex: currentTab,
                onDestinationSelected: select,
                destinations: [
                  for (final item in _navigationItems)
                    NavigationDestination(
                        icon: Icon(item.$2),
                        selectedIcon: Icon(item.$3),
                        label: item.$1)
                ],
              ),
      ),
    );
  }
}
