import 'package:flutter/material.dart';

class AppColors {
  static const teal = Color(0xFF008C98);
  static const tealDark = Color(0xFF006E78);
  static const ink = Color(0xFF141719);
  static const bg = Color(0xFFF6F8F8);
  static const success = Color(0xFF22A95B);
  static const warning = Color(0xFFF4A300);
  static const danger = Color(0xFFE33D3D);
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
    textTheme: const TextTheme(
      headlineMedium: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.6),
      titleLarge: TextStyle(fontWeight: FontWeight.w800),
      titleMedium: TextStyle(fontWeight: FontWeight.w700),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.teal,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
  );
}
