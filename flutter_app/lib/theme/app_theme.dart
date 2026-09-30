import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Centralized Design System & Color Palette for MONA (design.md 9.1)
/// Blue + White Palette:
/// - primary: #2F6FED / #3B7DEB
/// - surface: #FFFFFF
/// - surfaceAlt: #EAF1FD (Page background with soft blue tint)
/// - textPrimary: #1A1A1A
/// - textSecondary: #64748B
class AppTheme {
  static const Color primary = Color(0xFF2F6FED);
  static const Color primaryDark = Color(0xFF1B4EAE);
  static const Color primaryLight = Color(0xFF538AF7);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceAlt = Color(0xFFEAF1FD);
  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color borderLight = Color(0xFFD4E2FC);
  static const Color cardBorder = Color(0xFFE2EBFB);
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: surfaceAlt,
      colorScheme: const ColorScheme.light(
        primary: primary,
        secondary: primaryDark,
        surface: surface,
        error: danger,
        onPrimary: Colors.white,
        onSurface: textPrimary,
      ),
      textTheme: GoogleFonts.poppinsTextTheme().copyWith(
        titleLarge: GoogleFonts.poppins(
          color: textPrimary,
          fontWeight: FontWeight.w700,
          fontSize: 20,
        ),
        titleMedium: GoogleFonts.poppins(
          color: textPrimary,
          fontWeight: FontWeight.w600,
          fontSize: 16,
        ),
        bodyLarge: GoogleFonts.poppins(
          color: textPrimary,
          fontSize: 14,
        ),
        bodyMedium: GoogleFonts.poppins(
          color: textSecondary,
          fontSize: 13,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
    );
  }
}
