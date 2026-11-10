// lib/core/theme/app_theme.dart

import 'package:flutter/material.dart';

enum AppThemeKind {
  midnight('midnight', 'Ciemny fiolet'),
  graphite('graphite', 'Grafit i bursztyn'),
  sky('sky', 'Jasny błękit'),
  pearl('pearl', 'Jasny rubin'),
  custom('custom', 'Własny');

  const AppThemeKind(this.storageValue, this.label);

  final String storageValue;
  final String label;

  static AppThemeKind fromStorage(String? value) {
    if (value == 'ocean') return AppThemeKind.graphite;
    if (value == 'meadow') return AppThemeKind.pearl;
    return AppThemeKind.values.firstWhere(
      (theme) => theme.storageValue == value,
      orElse: () => AppThemeKind.midnight,
    );
  }
}

class _ThemePalette {
  const _ThemePalette({
    required this.primary,
    required this.secondary,
    required this.background,
    required this.surface,
    required this.surfaceVariant,
    required this.onSurface,
    required this.onSurfaceMuted,
    required this.error,
    required this.warning,
    required this.success,
    required this.breakBlock,
    required this.brightness,
  });

  final Color primary;
  final Color secondary;
  final Color background;
  final Color surface;
  final Color surfaceVariant;
  final Color onSurface;
  final Color onSurfaceMuted;
  final Color error;
  final Color warning;
  final Color success;
  final Color breakBlock;
  final Brightness brightness;
}

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
  static const _fontFamily = 'sans-serif';

  static ThemeData themeFor(AppThemeKind themeKind,
      {Map<String, Color> colors = const {}}) {
    AppColors.applyTheme(themeKind);
    if (themeKind == AppThemeKind.custom) AppColors.applyCustomColors(colors);
    final onPrimary = ThemeData.estimateBrightnessForColor(AppColors.primary) ==
            Brightness.light
        ? const Color(0xFF18181B)
        : Colors.white;
    return ThemeData(
      useMaterial3: true,
      brightness: AppColors.brightness,
      fontFamily: _fontFamily,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: AppColors.brightness,
        primary: AppColors.primary,
        onPrimary: onPrimary,
        secondary: AppColors.secondary,
        surface: AppColors.surface,
        onSurface: AppColors.onSurface,
        error: AppColors.error,
      ),
      scaffoldBackgroundColor: AppColors.background,
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      textTheme: TextTheme(
        headlineLarge: TextStyle(
            color: AppColors.onSurface,
            fontWeight: FontWeight.w700,
            fontSize: 28),
        headlineMedium: TextStyle(
            color: AppColors.onSurface,
            fontWeight: FontWeight.w600,
            fontSize: 22),
        headlineSmall: TextStyle(
            color: AppColors.onSurface,
            fontWeight: FontWeight.w600,
            fontSize: 18),
        titleLarge: TextStyle(
            color: AppColors.onSurface,
            fontWeight: FontWeight.w600,
            fontSize: 16),
        titleMedium: TextStyle(
            color: AppColors.onSurface,
            fontWeight: FontWeight.w500,
            fontSize: 14),
        bodyLarge: TextStyle(color: AppColors.onSurface, fontSize: 15),
        bodyMedium: TextStyle(color: AppColors.onSurfaceMuted, fontSize: 13),
        labelSmall: TextStyle(color: AppColors.onSurfaceMuted, fontSize: 11),
      ),
      appBarTheme: AppBarTheme(
        scrolledUnderElevation: 0,
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          fontFamily: _fontFamily,
        ),
        iconTheme: IconThemeData(color: AppColors.onSurface),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.surface,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.onSurfaceMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primary.withValues(alpha: 0.2),
        indicatorShape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        selectedIconTheme: IconThemeData(color: AppColors.primary),
        unselectedIconTheme: IconThemeData(color: AppColors.onSurfaceMuted),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        indicatorShape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primary.withValues(alpha: 0.2),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
                color: AppColors.primary,
                fontSize: 12,
                fontWeight: FontWeight.w600);
          }
          return TextStyle(color: AppColors.onSurfaceMuted, fontSize: 12);
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: AppColors.primary);
          }
          return IconThemeData(color: AppColors.onSurfaceMuted);
        }),
      ),
      dividerTheme: DividerThemeData(
        color: AppColors.onSurfaceMuted.withValues(alpha: 0.15),
        thickness: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.primary, width: 2),
        ),
        labelStyle: TextStyle(color: AppColors.onSurfaceMuted),
        hintStyle: TextStyle(color: AppColors.onSurfaceMuted),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.primary;
          return AppColors.onSurfaceMuted;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.primary.withValues(alpha: 0.4);
          }
          return AppColors.onSurfaceMuted.withValues(alpha: 0.2);
        }),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceVariant,
        labelStyle: TextStyle(
            color: AppColors.onSurface,
            fontSize: 12,
            fontWeight: FontWeight.w500),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      extensions: const [AppColors()],
    );
  }
}

class AppColors extends ThemeExtension<AppColors> {
  static Color primary = const Color(0xFF6C63FF);
  static Color secondary = const Color(0xFF03DAC6);
  static Color background = const Color(0xFF121212);
  static Color surface = const Color(0xFF1E1E2E);
  static Color surfaceVariant = const Color(0xFF2A2A3E);
  static Color onSurface = const Color(0xFFE2E2F0);
  static Color onSurfaceMuted = const Color(0xFF9090A8);
  static Color error = const Color(0xFFCF6679);
  static Color warning = const Color(0xFFFFB74D);
  static Color success = const Color(0xFF4CAF50);
  static Color breakBlock = const Color(0xFF252535);
  static Brightness brightness = Brightness.dark;

  static void applyCustomColors(Map<String, Color> colors) {
    primary = colors['primary'] ?? primary;
    secondary = colors['secondary'] ?? secondary;
    background = colors['background'] ?? background;
    surface = colors['surface'] ??
        (colors.containsKey('background')
            ? Color.lerp(
                background,
                background.computeLuminance() > 0.179
                    ? Colors.black
                    : Colors.white,
                0.07)!
            : surface);
    if (colors.containsKey('background') || colors.containsKey('surface')) {
      brightness = ThemeData.estimateBrightnessForColor(background);
      onSurface = background.computeLuminance() > 0.179
          ? const Color(0xFF151518)
          : const Color(0xFFF5F5F7);
      // Background labels and card labels share this foreground. Correct only
      // incompatible surface colors instead of leaving one of them unreadable.
      final chosenSurface = surface;
      for (var step = 0; step <= 20; step++) {
        surface = Color.lerp(chosenSurface, background, step / 20)!;
        final a = surface.computeLuminance();
        final b = onSurface.computeLuminance();
        final contrast =
            a > b ? (a + 0.05) / (b + 0.05) : (b + 0.05) / (a + 0.05);
        if (contrast >= 4.5) break;
      }
      onSurfaceMuted =
          readableAccent(Color.lerp(onSurface, surface, 0.3)!, surface);
      onSurfaceMuted = readableAccent(onSurfaceMuted, background);
      surfaceVariant = Color.lerp(surface, onSurface, 0.08)!;
      breakBlock = surfaceVariant;
    }
  }

  static void applyTheme(AppThemeKind theme) {
    final palette = switch (theme) {
      AppThemeKind.midnight || AppThemeKind.custom => const _ThemePalette(
          primary: Color(0xFF6C63FF),
          secondary: Color(0xFF03DAC6),
          background: Color(0xFF121212),
          surface: Color(0xFF1E1E2E),
          surfaceVariant: Color(0xFF2A2A3E),
          onSurface: Color(0xFFE2E2F0),
          onSurfaceMuted: Color(0xFF9090A8),
          error: Color(0xFFCF6679),
          warning: Color(0xFFFFB74D),
          success: Color(0xFF4CAF50),
          breakBlock: Color(0xFF252535),
          brightness: Brightness.dark),
      AppThemeKind.graphite => const _ThemePalette(
          primary: Color(0xFFE8B75C),
          secondary: Color(0xFF70C7B1),
          background: Color(0xFF141416),
          surface: Color(0xFF222225),
          surfaceVariant: Color(0xFF303035),
          onSurface: Color(0xFFF4F4F5),
          onSurfaceMuted: Color(0xFFA7A7B0),
          error: Color(0xFFF08B96),
          warning: Color(0xFFE8B75C),
          success: Color(0xFF74C69D),
          breakBlock: Color(0xFF2B2B30),
          brightness: Brightness.dark),
      AppThemeKind.sky => const _ThemePalette(
          primary: Color(0xFF2563EB),
          secondary: Color(0xFF0891B2),
          background: Color(0xFFF5F8FC),
          surface: Color(0xFFFFFFFF),
          surfaceVariant: Color(0xFFE6EEF8),
          onSurface: Color(0xFF172033),
          onSurfaceMuted: Color(0xFF637087),
          error: Color(0xFFC2415B),
          warning: Color(0xFFC47A10),
          success: Color(0xFF16824B),
          breakBlock: Color(0xFFDCE6F1),
          brightness: Brightness.light),
      AppThemeKind.pearl => const _ThemePalette(
          primary: Color(0xFFB52C56),
          secondary: Color(0xFF286C83),
          background: Color(0xFFF4F4F6),
          surface: Color(0xFFFFFFFF),
          surfaceVariant: Color(0xFFE9E9EE),
          onSurface: Color(0xFF242429),
          onSurfaceMuted: Color(0xFF666672),
          error: Color(0xFFBA253D),
          warning: Color(0xFF94610A),
          success: Color(0xFF23734D),
          breakBlock: Color(0xFFDEDEE5),
          brightness: Brightness.light),
    };
    primary = palette.primary;
    secondary = palette.secondary;
    background = palette.background;
    surface = palette.surface;
    surfaceVariant = palette.surfaceVariant;
    onSurface = palette.onSurface;
    onSurfaceMuted = palette.onSurfaceMuted;
    error = palette.error;
    warning = palette.warning;
    success = palette.success;
    breakBlock = palette.breakBlock;
    brightness = palette.brightness;
  }

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
    ScheduleColorOption(key: 'wyklad', label: 'Wykład', defaultColor: wyklad),
    ScheduleColorOption(
        key: 'cwiczenia', label: 'Ćwiczenia', defaultColor: cwiczenia),
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
        key: 'zerowka', label: 'Zerówka', defaultColor: zerowka),
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

  static Color readableAccent(Color accent, Color background) {
    final backgroundLuminance = background.computeLuminance();
    final target = backgroundLuminance > 0.179 ? Colors.black : Colors.white;
    // Zachowujemy odcień, korygując jasność tylko do czytelnego kontrastu.
    for (var step = 0; step <= 20; step++) {
      final candidate = Color.lerp(accent, target, step / 20)!;
      final luminance = candidate.computeLuminance();
      final contrast = luminance > backgroundLuminance
          ? (luminance + 0.05) / (backgroundLuminance + 0.05)
          : (backgroundLuminance + 0.05) / (luminance + 0.05);
      if (contrast >= 4.5) return candidate;
    }
    return target;
  }

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
