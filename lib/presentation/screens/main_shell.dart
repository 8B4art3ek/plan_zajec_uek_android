// lib/presentation/screens/main_shell.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'home/home_screen.dart';
import 'groups/groups_screen.dart';
import 'settings/settings_screen.dart';

final _currentTabProvider = StateProvider<int>((ref) => 0);

class MainShell extends ConsumerWidget {
  const MainShell({super.key});

  static const _tabs = [
    HomeScreen(),
    GroupsScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTab = ref.watch(_currentTabProvider);

    return Scaffold(
      body: IndexedStack(
        index: currentTab,
        children: _tabs,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentTab,
        onDestinationSelected: (i) =>
            ref.read(_currentTabProvider.notifier).state = i,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.today_rounded),
            label: 'Dzisiaj',
          ),
          NavigationDestination(
            icon: Icon(Icons.group_rounded),
            label: 'Grupy',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_rounded),
            label: 'Ustawienia',
          ),
        ],
      ),
    );
  }
}
