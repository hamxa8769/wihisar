/// WiHisar cyberpunk theme — dark, neon, futuristic, still lightweight.
///
/// No custom fonts and no image assets: the look comes from colour,
/// borders and spacing only, so the app stays small and fast.
library;

import 'package:flutter/material.dart';

class CyberpunkTheme {
  CyberpunkTheme._();

  /// Near-black blue background.
  static const background = Color(0xFF05060A);

  /// Panel / card surface.
  static const surface = Color(0xFF0B0F1A);

  /// Slightly raised surface (inputs, sliders track).
  static const surfaceRaised = Color(0xFF121829);

  /// Primary neon: cyan.
  static const neonCyan = Color(0xFF00F0FF);

  /// Secondary neon: magenta.
  static const neonMagenta = Color(0xFFFF2E88);

  /// Tertiary neon: lime, used for "safe / OK" states.
  static const neonLime = Color(0xFF9DFF00);

  /// Warning amber.
  static const warnAmber = Color(0xFFFFB800);

  static const textPrimary = Color(0xFFE8F6FF);
  static const textMuted = Color(0xFF8A94A8);

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    final scheme = const ColorScheme.dark(
      primary: neonCyan,
      secondary: neonMagenta,
      tertiary: neonLime,
      surface: surface,
      error: neonMagenta,
      onPrimary: background,
      onSecondary: background,
      onSurface: textPrimary,
    );
    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      textTheme: base.textTheme.apply(
        bodyColor: textPrimary,
        displayColor: textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: textPrimary,
        centerTitle: false,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: neonCyan.withValues(alpha: 0.35)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceRaised,
        labelStyle: const TextStyle(color: textMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: neonCyan.withValues(alpha: 0.35)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: neonCyan.withValues(alpha: 0.35)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: neonCyan, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: neonCyan,
          foregroundColor: background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: neonCyan),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? neonMagenta
              : textMuted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? neonMagenta.withValues(alpha: 0.4)
              : surfaceRaised,
        ),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: neonCyan,
        inactiveTrackColor: surfaceRaised,
        thumbColor: neonMagenta,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: background,
        indicatorColor: neonCyan.withValues(alpha: 0.2),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(color: textPrimary, fontSize: 12),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: neonCyan.withValues(alpha: 0.2),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: surfaceRaised,
        contentTextStyle: TextStyle(color: textPrimary),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: neonCyan.withValues(alpha: 0.4)),
        ),
      ),
    );
  }

  /// Monospace display style for headings / version tags / hashes.
  static const TextStyle display = TextStyle(
    fontFamily: 'monospace',
    color: textPrimary,
    fontWeight: FontWeight.bold,
    letterSpacing: 0.5,
  );

  /// Neon glow border used by [CyberCard] (see widgets/cyber_widgets.dart).
  static BoxDecoration panelDecoration({Color accent = neonCyan}) {
    return BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: accent.withValues(alpha: 0.45)),
      boxShadow: [
        BoxShadow(
          color: accent.withValues(alpha: 0.12),
          blurRadius: 18,
          spreadRadius: 1,
        ),
      ],
    );
  }
}
