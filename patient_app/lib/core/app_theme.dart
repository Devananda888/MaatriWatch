import 'package:flutter/material.dart';

import 'design_tokens.dart';

ThemeData maatriTheme() {
  final baseText = MaatriTokens.type(size: MaatriTokens.type16);
  final textTheme = TextTheme(
    displaySmall: MaatriTokens.type(
      size: MaatriTokens.type32,
      weight: FontWeight.w900,
      height: 1.2,
    ),
    headlineSmall: MaatriTokens.type(
      size: MaatriTokens.type24,
      weight: FontWeight.w800,
      height: 1.25,
    ),
    titleLarge: MaatriTokens.type(
      size: MaatriTokens.type20,
      weight: FontWeight.w800,
      height: 1.3,
    ),
    titleMedium: MaatriTokens.type(
      size: MaatriTokens.type16,
      weight: FontWeight.w800,
    ),
    bodyLarge: baseText,
    bodyMedium: MaatriTokens.type(size: MaatriTokens.type14),
    bodySmall: MaatriTokens.type(
      size: MaatriTokens.type12,
      color: MaatriTokens.textMuted,
    ),
    labelLarge: MaatriTokens.type(
      size: MaatriTokens.type14,
      weight: FontWeight.w700,
    ),
  );
  final scheme = ColorScheme.fromSeed(
    seedColor: MaatriTokens.primary,
    brightness: Brightness.light,
    primary: MaatriTokens.primary,
    onPrimary: Colors.white,
    secondary: MaatriTokens.indigo,
    onSecondary: Colors.white,
    surface: MaatriTokens.surface,
    onSurface: MaatriTokens.text,
    error: MaatriTokens.critical,
    onError: Colors.white,
  );
  final outline = OutlineInputBorder(
    borderRadius: BorderRadius.circular(MaatriTokens.radius12),
    borderSide: const BorderSide(color: MaatriTokens.border),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: MaatriTokens.canvas,
    textTheme: textTheme,
    fontFamily: MaatriTokens.fontFamily,
    fontFamilyFallback: MaatriTokens.fontFallbacks,
    dividerColor: MaatriTokens.border,
    appBarTheme: AppBarTheme(
      backgroundColor: MaatriTokens.surface,
      foregroundColor: MaatriTokens.text,
      elevation: 0,
      scrolledUnderElevation: 1,
      titleTextStyle: textTheme.titleLarge,
    ),
    cardTheme: CardThemeData(
      color: MaatriTokens.surface,
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.1),
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MaatriTokens.radius12),
        side: const BorderSide(color: MaatriTokens.border, width: 0.5),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: MaatriTokens.surface,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: MaatriTokens.space16,
        vertical: MaatriTokens.space12,
      ),
      border: outline,
      enabledBorder: outline,
      focusedBorder: outline.copyWith(
        borderSide: const BorderSide(color: MaatriTokens.focus, width: 2),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(0, MaatriTokens.primaryControlHeight),
        padding: const EdgeInsets.symmetric(horizontal: MaatriTokens.space24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MaatriTokens.radius12),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, MaatriTokens.controlHeight),
        side: const BorderSide(color: MaatriTokens.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MaatriTokens.radius12),
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MaatriTokens.radius8),
      ),
      side: BorderSide.none,
    ),
  );
}
