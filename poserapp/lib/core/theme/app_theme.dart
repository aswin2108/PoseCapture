import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static const background = Color(0xFF000000);
  static const surface = Color(0xFF1C1C1E);
  static const surfaceVariant = Color(0xFF2C2C2E);
  static const primary = Color(0xFFFFFFFF);
  static const secondary = Color(0xFF00E5FF);
  static const onSurface = Color(0xFFEBEBF5);
  static const subtle = Color(0xFF8E8E93);

  static final dark = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: background,
    colorScheme: const ColorScheme.dark(
      surface: surface,
      primary: primary,
      secondary: secondary,
      onPrimary: background,
      onSurface: onSurface,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      iconTheme: IconThemeData(color: primary),
      titleTextStyle: TextStyle(
        color: primary,
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.4,
      ),
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        color: primary,
        fontSize: 34,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      headlineMedium: TextStyle(
        color: primary,
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
      titleLarge: TextStyle(
        color: primary,
        fontSize: 22,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
      ),
      bodyLarge: TextStyle(
        color: onSurface,
        fontSize: 17,
        letterSpacing: -0.2,
        height: 1.5,
      ),
      bodyMedium: TextStyle(
        color: onSurface,
        fontSize: 15,
        letterSpacing: -0.1,
      ),
      labelLarge: TextStyle(
        color: primary,
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: background,
        minimumSize: const Size(double.infinity, 56),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        textStyle: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
        elevation: 0,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: secondary,
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
    iconTheme: const IconThemeData(color: primary, size: 24),
  );
}
