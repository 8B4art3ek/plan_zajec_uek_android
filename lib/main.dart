// lib/main.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'data/datasources/background_service.dart';
import 'data/datasources/notification_service.dart';
import 'presentation/providers/providers.dart';
import 'presentation/screens/login_screen.dart';
import 'presentation/screens/main_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Init notifications
  await NotificationService().init();
  await NotificationService().requestPermission();

  // Init background refresh
  await BackgroundService.init();
  await BackgroundService.schedulePeriodicRefresh();

  runApp(const ProviderScope(child: PlanZajecApp()));
}

class PlanZajecApp extends ConsumerWidget {
  const PlanZajecApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Plan Zajec UEK',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      initialRoute: '/splash',
      routes: {
        '/splash': (_) => const SplashScreen(),
        '/login': (_) => const LoginScreen(),
        '/home': (_) => const MainShell(),
      },
    );
  }
}

class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLoggedIn = ref.watch(isLoggedInProvider);

    return isLoggedIn.when(
      loading: () => const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.school_rounded, color: AppColors.primary, size: 64),
              SizedBox(height: 24),
              Text(
                'Plan Zajec UEK',
                style: TextStyle(
                  color: AppColors.onSurface,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 32),
              CircularProgressIndicator(color: AppColors.primary),
            ],
          ),
        ),
      ),
      error: (_, __) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Navigator.of(context).pushReplacementNamed('/login');
        });
        return const Scaffold(body: SizedBox.shrink());
      },
      data: (loggedIn) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (loggedIn) {
            Navigator.of(context).pushReplacementNamed('/home');
          } else {
            Navigator.of(context).pushReplacementNamed('/login');
          }
        });
        return const Scaffold(
          body: Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
        );
      },
    );
  }
}
