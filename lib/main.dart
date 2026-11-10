// lib/main.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/app_identity.dart';
import 'core/theme/app_theme.dart';
import 'data/datasources/background_service.dart';
import 'data/datasources/notification_service.dart';
import 'presentation/providers/providers.dart';
import 'presentation/screens/login_screen.dart';
import 'presentation/screens/main_shell.dart';
import 'presentation/screens/university_screen.dart';
import 'presentation/widgets/app_viewport.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Init notifications
  await NotificationService().init();
  await NotificationService().requestPermission();

  // Init background refresh
  await BackgroundService.init();
  await BackgroundService.schedulePeriodicRefresh();

  runApp(ProviderScope(child: PlanZajecApp()));
}

class PlanZajecApp extends ConsumerWidget {
  PlanZajecApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedTheme =
        ref.watch(appThemeProvider).valueOrNull ?? AppThemeKind.midnight;
    return MaterialApp(
      title: appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.themeFor(selectedTheme,
          colors: ref.watch(customThemeColorsProvider).valueOrNull ?? const {}),
      themeMode: ThemeMode.light,
      builder: (context, child) => AppViewport(child: child!),
      initialRoute: '/splash',
      routes: {
        '/splash': (_) => SplashScreen(),
        '/login': (_) => LoginScreen(),
        '/university': (_) => const UniversityScreen(),
        '/home': (_) => MainShell(),
      },
    );
  }
}

class SplashScreen extends ConsumerStatefulWidget {
  SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  bool _navigating = false;

  void _navigate(String route) {
    if (_navigating) return;
    _navigating = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pushReplacementNamed(route);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = ref.watch(isLoggedInProvider);
    final university = ref.watch(universityProvider);

    return isLoggedIn.when(
      loading: () => Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(appIconAsset, width: 80, height: 80),
              SizedBox(height: 24),
              Text(
                appName,
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
        _navigate('/university');
        return Scaffold(body: SizedBox.shrink());
      },
      data: (loggedIn) {
        if (!loggedIn && university.isLoading) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        _navigate(loggedIn
            ? '/home'
            : university.valueOrNull == null
                ? '/university'
                : '/login');
        return Scaffold(
          body: Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
        );
      },
    );
  }
}
