import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // ── COLOURS ────────────────────────────────────────────
  static const Color bgPrimary       = Color(0xFF0D0D0D);
  static const Color bgSecondary     = Color(0xFF1A0A0F);
  static const Color surfaceCard     = Color(0xFF1E1018);
  static const Color surfaceElevated = Color(0xFF2A1020);

  static const Color pink            = Color(0xFFE91E8C);
  static const Color pinkLight       = Color(0xFFFF6EB4);
  static const Color pinkMuted       = Color(0xFF7B1A4A);

  static const Color gold            = Color(0xFFD4AF37);
  static const Color goldLight       = Color(0xFFF0D060);

  static const Color textPrimary     = Color(0xFFFAF0F5);
  static const Color textSecondary   = Color(0xFFBFA8B8);
  static const Color textTertiary    = Color(0xFF7A5A70);

  static const Color success         = Color(0xFF00C896);
  static const Color warning         = Color(0xFFFFB347);
  static const Color error           = Color(0xFFFF3B5C);
  static const Color criticalPulse   = Color(0xFFE91E8C);

  static const Color patientBg       = Color(0xFF1A0A0F);
  static const Color doctorBg        = Color(0xFF0D0D0F);

  // ── GRADIENTS ──────────────────────────────────────────
  static const LinearGradient pinkGradient = LinearGradient(
    colors: [Color(0xFFE91E8C), Color(0xFF7B1A4A)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const RadialGradient bgGradient = RadialGradient(
    center: Alignment(0.3, -0.6),
    radius: 1.4,
    colors: [Color(0xFF2A0A18), Color(0xFF0D0D0D)],
  );

  // ── SHADOWS ────────────────────────────────────────────
  static List<BoxShadow> pinkGlow = [
    BoxShadow(
      color: const Color(0xFFE91E8C).withOpacity(0.20),
      blurRadius: 20,
      spreadRadius: -2,
    ),
  ];

  static List<BoxShadow> cardShadow = [
    const BoxShadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 6)),
    BoxShadow(
      color: const Color(0xFFE91E8C).withOpacity(0.08),
      blurRadius: 20,
      spreadRadius: -4,
      offset: const Offset(0, 4),
    ),
  ];

  // ── TEXT STYLES ────────────────────────────────────────
  static TextStyle get headline => GoogleFonts.playfairDisplay(
    fontSize: 28, fontWeight: FontWeight.w300,
    color: textPrimary, letterSpacing: 0.5,
  );

  static TextStyle get headlineLarge => GoogleFonts.playfairDisplay(
    fontSize: 32, fontWeight: FontWeight.w300,
    color: textPrimary, letterSpacing: 0.5,
  );

  static TextStyle get subhead => GoogleFonts.dmSans(
    fontSize: 16, fontWeight: FontWeight.w600,
    color: textPrimary, letterSpacing: 0.3,
  );

  static TextStyle get body => GoogleFonts.dmSans(
    fontSize: 14, fontWeight: FontWeight.w400,
    color: textSecondary,
  );

  static TextStyle get bodySmall => GoogleFonts.dmSans(
    fontSize: 13, fontWeight: FontWeight.w400,
    color: textSecondary,
  );

  static TextStyle get vitalNumber => GoogleFonts.playfairDisplay(
    fontSize: 48, fontWeight: FontWeight.w300,
    color: textPrimary,
  );

  static TextStyle get caption => GoogleFonts.dmSans(
    fontSize: 11, fontWeight: FontWeight.w400,
    color: textTertiary, letterSpacing: 0.5,
  );

  static TextStyle get affirmation => GoogleFonts.playfairDisplay(
    fontSize: 18, fontStyle: FontStyle.italic,
    fontWeight: FontWeight.w400, color: textPrimary, height: 1.6,
  );

  static TextStyle get label => GoogleFonts.dmSans(
    fontSize: 12, fontWeight: FontWeight.w600,
    color: textSecondary, letterSpacing: 0.3,
  );

  static TextStyle get buttonText => GoogleFonts.dmSans(
    fontSize: 16, fontWeight: FontWeight.w600,
    color: Colors.white, letterSpacing: 0.5,
  );

  // ── CARD DECORATION ───────────────────────────────────
  static BoxDecoration get cardDecoration => BoxDecoration(
    color: surfaceCard.withOpacity(0.85),
    borderRadius: BorderRadius.circular(16),
    border: Border.all(
      color: pinkMuted.withOpacity(0.4),
      width: 1,
    ),
    boxShadow: cardShadow,
  );

  static BoxDecoration vitalsCardDecoration(String status) => BoxDecoration(
    color: surfaceCard.withOpacity(0.85),
    borderRadius: BorderRadius.circular(16),
    border: Border(
      left: BorderSide(
        color: status == 'normal'
            ? success
            : status == 'warning'
                ? warning
                : pink,
        width: 3,
      ),
      top: BorderSide(color: pinkMuted.withOpacity(0.3), width: 1),
      right: BorderSide(color: pinkMuted.withOpacity(0.3), width: 1),
      bottom: BorderSide(color: pinkMuted.withOpacity(0.3), width: 1),
    ),
    boxShadow: cardShadow,
  );

  // ── INPUT DECORATION ──────────────────────────────────
  static InputDecoration inputDecoration(String hint, {IconData? icon}) =>
      InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: surfaceElevated,
        hintStyle: TextStyle(color: textTertiary),
        prefixIcon: icon != null ? Icon(icon, color: pinkMuted, size: 20) : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: pinkMuted, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: pinkMuted, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: pink, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: error, width: 1.5),
        ),
      );

  // ── THEME DATA ─────────────────────────────────────────
  static ThemeData get darkTheme => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bgPrimary,
        colorScheme: ColorScheme.dark(
          primary: pink,
          secondary: gold,
          surface: surfaceCard,
          error: error,
          onPrimary: Colors.white,
          onSurface: textPrimary,
        ),
        cardTheme: CardTheme(
          color: surfaceCard,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          elevation: 0,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: surfaceElevated,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: pinkMuted, width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: pink, width: 1.5),
          ),
          hintStyle: const TextStyle(color: textTertiary),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: pink,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: bgPrimary,
          elevation: 0,
          titleTextStyle: GoogleFonts.playfairDisplay(
            fontSize: 20,
            fontWeight: FontWeight.w300,
            color: textPrimary,
          ),
          iconTheme: const IconThemeData(color: textPrimary),
        ),
        iconTheme: const IconThemeData(color: textPrimary),
        dividerColor: pinkMuted.withOpacity(0.3),
      );
}
