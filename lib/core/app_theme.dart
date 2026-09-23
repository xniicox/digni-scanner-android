import 'package:flutter/material.dart';

class AppColors {
  static const teal = Color(0xFF008C98);
  static const tealBright = Color(0xFF11C7C6);
  static const tealDark = Color(0xFF006D77);
  static const ink = Color(0xFF171A1C);
  static const muted = Color(0xFF667176);
  static const bg = Color(0xFFF4F7F7);
  static const line = Color(0xFFDDE5E6);
  static const success = Color(0xFF1DAA5B);
  static const warning = Color(0xFFF3A712);
  static const danger = Color(0xFFDC3C45);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.teal,
    brightness: Brightness.light,
    surface: AppColors.bg,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bg,
    splashFactory: InkSparkle.splashFactory,
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontWeight: FontWeight.w900,
        letterSpacing: -1.2,
        color: AppColors.ink,
      ),
      headlineMedium: TextStyle(
        fontWeight: FontWeight.w850,
        letterSpacing: -0.7,
        color: AppColors.ink,
      ),
      titleLarge: TextStyle(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.3,
        color: AppColors.ink,
      ),
      titleMedium: TextStyle(
        fontWeight: FontWeight.w750,
        color: AppColors.ink,
      ),
      bodyLarge: TextStyle(height: 1.3, color: AppColors.ink),
      bodyMedium: TextStyle(height: 1.35, color: AppColors.muted),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: Color(0x11008C98)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.teal,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(56),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w800,
          letterSpacing: .1,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      hintStyle: const TextStyle(color: Color(0xFF8B969A)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: AppColors.teal, width: 1.5),
      ),
    ),
  );
}
