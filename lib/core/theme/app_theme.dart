// lib/core/theme/app_theme.dart

import 'package:flutter/material.dart';

class ScheduleColorOption {
  final String key;
  final String label;
  final Color defaultColor;

  const ScheduleColorOption({
    required this.key,
    required this.label,
    required this.defaultColor,
  });
}

class AppTheme {
  static const _primary = Color(0xFF6C63FF);
  static const _secondary = Color(0xFF03DAC6);
  static const _background = Color(0xFF121212);
  static const _surface = Color(0xFF1E1E2E);
  static const _surfaceVariant = Color(0xFF2A2A3E);
  static const _onSurface = Color(0xFFE2E2F0);
  static const _onSurfaceMuted = Color(0xFF9090A8);
  static const _error = Color(0xFFCF6679);

  static const _fontFamily = 'sans-serif';

  static ThemeData get darkTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        fontFamily: _fontFamily,
        colorScheme: const ColorScheme.dark(
          primary: _primary,
          secondary: _secondary,
          surface: _surface,
          onSurface: _onSurface,
          error: _error,
        ),
        scaffoldBackgroundColor: _background,
        cardTheme: CardThemeData(
          color: _surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        textTheme: const TextTheme(
          headlineLarge: TextStyle(
              color: _onSurface, fontWeight: FontWeight.w700, fontSize: 28),
          headlineMedium: TextStyle(
              color: _onSurface, fontWeight: FontWeight.w600, fontSize: 22),
          headlineSmall: TextStyle(
              color: _onSurface, fontWeight: FontWeight.w600, fontSize: 18),
          titleLarge: TextStyle(
              color: _onSurface, fontWeight: FontWeight.w600, fontSize: 16),
          titleMedium: TextStyle(
              color: _onSurface, fontWeight: FontWeight.w500, fontSize: 14),
          bodyLarge: TextStyle(color: _onSurface, fontSize: 15),
          bodyMedium: TextStyle(color: _onSurfaceMuted, fontSize: 13),
          labelSmall: TextStyle(color: _onSurfaceMuted, fontSize: 11),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: _background,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: _onSurface,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            fontFamily: _fontFamily,
          ),
          iconTheme: IconThemeData(color: _onSurface),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: _surface,
          selectedItemColor: _primary,
          unselectedItemColor: _onSurfaceMuted,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: _surface,
          indicatorColor: _primary.withValues(alpha: 0.2),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const TextStyle(
                  color: _primary, fontSize: 12, fontWeight: FontWeight.w600);
            }
            return const TextStyle(color: _onSurfaceMuted, fontSize: 12);
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const IconThemeData(color: _primary);
            }
            return const IconThemeData(color: _onSurfaceMuted);
          }),
        ),
        dividerTheme: DividerThemeData(
          color: _onSurfaceMuted.withValues(alpha: 0.15),
          thickness: 1,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: _surfaceVariant,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _primary, width: 2),
          ),
          labelStyle: const TextStyle(color: _onSurfaceMuted),
          hintStyle: const TextStyle(color: _onSurfaceMuted),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: _primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            textStyle:
                const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return _primary;
            return _onSurfaceMuted;
          }),
          trackColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return _primary.withValues(alpha: 0.4);
            }
            return _onSurfaceMuted.withValues(alpha: 0.2);
          }),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: _surfaceVariant,
          labelStyle: const TextStyle(
              color: _onSurface, fontSize: 12, fontWeight: FontWeight.w500),
          side: BorderSide.none,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        extensions: const [AppColors()],
      );
}

class AppColors extends ThemeExtension<AppColors> {
  static const primary = Color(0xFF6C63FF);
  static const secondary = Color(0xFF03DAC6);
  static const background = Color(0xFF121212);
  static const surface = Color(0xFF1E1E2E);
  static const surfaceVariant = Color(0xFF2A2A3E);
  static const onSurface = Color(0xFFE2E2F0);
  static const onSurfaceMuted = Color(0xFF9090A8);
  static const error = Color(0xFFCF6679);
  static const warning = Color(0xFFFFB74D);
  static const success = Color(0xFF4CAF50);
  static const breakBlock = Color(0xFF252535);

  // Class type colors
  static const wyklad = Color(0xFF9D6CFF);
  static const cwiczenia = Color(0xFF38BDF8);
  static const lektorat = Color(0xFF4ADE80);
  static const laboratorium = Color(0xFFFFB020);
  static const seminarium = Color(0xFFFF5C8A);
  static const wf = Color(0xFF22D3EE);
  static const egzamin = Color(0xFFFF6B6B);
  static const zerowka = Color(0xFFF59E0B);
  static const kolos = Color(0xFFFACC15);
  static const wydarzenie = Color(0xFFA78BFA);
  static const other = Color(0xFF94A3B8);

  static const scheduleColorOptions = [
    ScheduleColorOption(key: 'wyklad', label: 'Wyklad', defaultColor: wyklad),
    ScheduleColorOption(
        key: 'cwiczenia', label: 'Cwiczenia', defaultColor: cwiczenia),
    ScheduleColorOption(
        key: 'lektorat', label: 'Lektorat', defaultColor: lektorat),
    ScheduleColorOption(
        key: 'laboratorium', label: 'Laboratorium', defaultColor: laboratorium),
    ScheduleColorOption(
        key: 'seminarium', label: 'Seminarium', defaultColor: seminarium),
    ScheduleColorOption(key: 'wf', label: 'WF', defaultColor: wf),
    ScheduleColorOption(
        key: 'egzamin', label: 'Egzamin', defaultColor: egzamin),
    ScheduleColorOption(
        key: 'zerowka', label: 'Zerowka', defaultColor: zerowka),
    ScheduleColorOption(key: 'kolos', label: 'Kolos', defaultColor: kolos),
    ScheduleColorOption(
        key: 'wydarzenie', label: 'Wydarzenie', defaultColor: wydarzenie),
    ScheduleColorOption(key: 'inne', label: 'Inne', defaultColor: other),
  ];

  const AppColors();

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) => this;

  static Color classTypeColor(
    String classType, [
    Map<String, Color>? overrides,
  ]) {
    final key = classTypeKey(classType);
    final override = overrides?[key];
    if (override != null) return override;

    for (final option in scheduleColorOptions) {
      if (option.key == key) return option.defaultColor;
    }

    return other;
  }

  static String colorSettingKey(String key) => 'class_color_$key';

  static String classTypeKey(String classType) {
    final lower = classType.toLowerCase();
    if (lower.contains('egz')) return 'egzamin';
    if (lower.contains('zerow') || lower.contains('zerów')) return 'zerowka';
    if (lower.contains('kolos') || lower.contains('kolokw')) return 'kolos';
    if (lower.contains('wydarzenie')) return 'wydarzenie';
    if (lower.contains('wyk')) return 'wyklad';
    if (lower.contains('cwicz') ||
        lower.contains('ćwicz') ||
        lower.contains('cwi') ||
        lower.contains('ćwi')) {
      return 'cwiczenia';
    }
    if (lower.contains('lektorat')) return 'lektorat';
    if (lower.contains('laborat')) return 'laboratorium';
    if (lower.contains('seminar')) return 'seminarium';
    if (lower.contains('wf') || lower.contains('wychowanie')) return 'wf';
    return 'inne';
  }
}
