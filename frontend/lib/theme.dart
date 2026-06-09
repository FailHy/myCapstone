import 'package:flutter/material.dart';

class AppTheme {
  // Brand Colors
  static const Color primaryNavy = Color(0xFF0B0F2F);
  static const Color accentLime = Color(0xFFD6FF3F);
  static const Color surfaceDark = Color(0xFF1A1F4C);
  static const Color textLight = Colors.white;
  static const Color textGrey = Colors.white70;

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: primaryNavy,
      colorScheme: const ColorScheme.dark(
        primary: accentLime,
        surface: surfaceDark,
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          color: textLight,
          fontWeight: FontWeight.bold,
          fontSize: 32,
        ),
        titleLarge: TextStyle(
          color: textLight,
          fontWeight: FontWeight.bold,
          fontSize: 24,
        ),
        bodyLarge: TextStyle(color: textLight, fontSize: 16),
        bodyMedium: TextStyle(color: textGrey, fontSize: 14),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceDark,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: accentLime, width: 2),
        ),
        hintStyle: const TextStyle(color: Colors.white38),
      ),
    );
  }
}
