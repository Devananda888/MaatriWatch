import 'package:flutter/material.dart';

/// The only source of visual constants for the MaatriWatch Flutter apps.
///
/// The regional Noto fallbacks avoid a runtime font download. Deployments should
/// bundle the matching Noto font files when their target devices do not ship
/// them already; every screen uses this common stack.
abstract final class MaatriTokens {
  static const primary = Color(0xFF1B4B5A);
  static const primaryDark = Color(0xFF10333E);
  static const indigo =
      Color(0xFF1B4B5A); // Aligning secondary with primary family
  static const canvas = Color(0xFFF7F5F2);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceMuted = Color(0xFFEBE8E3);
  static const text = Color(0xFF14221F);
  static const textMuted = Color(0xFF52605B);
  static const border = Color(0xFFD7E0DC);
  static const success = Color(0xFF4CAF50);
  static const warning = Color(0xFFFFC107);
  static const alertCoral = Color(0xFFE5534B);
  static const critical = Color(0xFFE5534B); // Critical uses warm coral/red
  static const focus = Color(0xFF1B4B5A);

  static const space4 = 4.0;
  static const space8 = 8.0;
  static const space12 = 12.0;
  static const space16 = 16.0;
  static const space24 = 24.0;
  static const space32 = 32.0;
  static const space48 = 48.0;

  static const radius8 = 8.0;
  static const radius12 = 12.0;
  static const radius16 = 16.0;
  static const controlHeight = 44.0;
  static const primaryControlHeight = 48.0;

  static const type12 = 12.0;
  static const type14 = 14.0;
  static const type16 = 16.0;
  static const type20 = 20.0;
  static const type24 = 28.0; // Increased contrast for headings
  static const type32 = 36.0;

  static const fontFamily = 'Inter';
  static const fontFallbacks = <String>[
    'Noto Sans Devanagari',
    'Noto Sans Bengali',
    'Noto Sans Gujarati',
    'Noto Sans Gurmukhi',
    'Noto Sans Kannada',
    'Noto Sans Malayalam',
    'Noto Sans Tamil',
    'Noto Sans Telugu',
    'Noto Sans Oriya',
    'Noto Sans Arabic',
    'Noto Sans Ol Chiki',
    'Noto Sans Meetei Mayek',
    'sans-serif',
  ];

  static TextStyle type({
    required double size,
    FontWeight weight = FontWeight.w400,
    Color color = text,
    double height = 1.4,
  }) =>
      TextStyle(
        fontFamily: fontFamily,
        fontFamilyFallback: fontFallbacks,
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height,
      );

  static Color statusColor(String status) => switch (status) {
        'critical' => critical,
        'warning' => warning,
        'info' => indigo,
        'normal' => success,
        _ => textMuted,
      };
}
