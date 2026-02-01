import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Centralized typography styles using Poppins font
class AppTypography {
  // Font weights
  static const FontWeight light = FontWeight.w300;
  static const FontWeight regular = FontWeight.w400;
  static const FontWeight medium = FontWeight.w500;
  static const FontWeight semiBold = FontWeight.w600;
  static const FontWeight bold = FontWeight.w700;
  static const FontWeight black = FontWeight.w900;

  // Display styles (for hero/landing sections)
  static TextStyle displayLarge({Color? color}) => GoogleFonts.poppins(
    fontSize: 64,
    fontWeight: black,
    height: 1.1,
    color: color,
    letterSpacing: -0.5,
  );

  static TextStyle displayMedium({Color? color}) => GoogleFonts.poppins(
    fontSize: 48,
    fontWeight: bold,
    height: 1.2,
    color: color,
    letterSpacing: -0.25,
  );

  static TextStyle displaySmall({Color? color}) => GoogleFonts.poppins(
    fontSize: 36,
    fontWeight: bold,
    height: 1.2,
    color: color,
  );

  // Headline styles
  static TextStyle headlineLarge({Color? color}) => GoogleFonts.poppins(
    fontSize: 32,
    fontWeight: bold,
    height: 1.3,
    color: color,
  );

  static TextStyle headlineMedium({Color? color}) => GoogleFonts.poppins(
    fontSize: 24,
    fontWeight: semiBold,
    height: 1.3,
    color: color,
  );

  static TextStyle headlineSmall({Color? color}) => GoogleFonts.poppins(
    fontSize: 20,
    fontWeight: semiBold,
    height: 1.4,
    color: color,
  );

  // Title styles
  static TextStyle titleLarge({Color? color}) => GoogleFonts.poppins(
    fontSize: 18,
    fontWeight: semiBold,
    height: 1.4,
    color: color,
  );

  static TextStyle titleMedium({Color? color}) => GoogleFonts.poppins(
    fontSize: 16,
    fontWeight: medium,
    height: 1.4,
    color: color,
  );

  static TextStyle titleSmall({Color? color}) => GoogleFonts.poppins(
    fontSize: 14,
    fontWeight: medium,
    height: 1.4,
    color: color,
  );

  // Body styles
  static TextStyle bodyLarge({Color? color}) => GoogleFonts.poppins(
    fontSize: 16,
    fontWeight: regular,
    height: 1.5,
    color: color,
  );

  static TextStyle bodyMedium({Color? color}) => GoogleFonts.poppins(
    fontSize: 14,
    fontWeight: regular,
    height: 1.5,
    color: color,
  );

  static TextStyle bodySmall({Color? color}) => GoogleFonts.poppins(
    fontSize: 12,
    fontWeight: regular,
    height: 1.5,
    color: color,
  );

  // Label styles (for buttons, badges)
  static TextStyle labelLarge({Color? color}) => GoogleFonts.poppins(
    fontSize: 14,
    fontWeight: medium,
    height: 1.4,
    color: color,
    letterSpacing: 0.1,
  );

  static TextStyle labelMedium({Color? color}) => GoogleFonts.poppins(
    fontSize: 12,
    fontWeight: medium,
    height: 1.4,
    color: color,
    letterSpacing: 0.5,
  );

  static TextStyle labelSmall({Color? color}) => GoogleFonts.poppins(
    fontSize: 11,
    fontWeight: medium,
    height: 1.4,
    color: color,
    letterSpacing: 0.5,
  );

  // Special styles
  static TextStyle button({Color? color}) => GoogleFonts.poppins(
    fontSize: 14,
    fontWeight: semiBold,
    height: 1.4,
    color: color,
    letterSpacing: 0.75,
  );

  static TextStyle caption({Color? color}) => GoogleFonts.poppins(
    fontSize: 12,
    fontWeight: regular,
    height: 1.4,
    color: color,
  );

  static TextStyle overline({Color? color}) => GoogleFonts.poppins(
    fontSize: 10,
    fontWeight: medium,
    height: 1.4,
    color: color,
    letterSpacing: 1.5,
  );

  // Create complete TextTheme for Material
  static TextTheme createTextTheme() => TextTheme(
    displayLarge: displayLarge(),
    displayMedium: displayMedium(),
    displaySmall: displaySmall(),
    headlineLarge: headlineLarge(),
    headlineMedium: headlineMedium(),
    headlineSmall: headlineSmall(),
    titleLarge: titleLarge(),
    titleMedium: titleMedium(),
    titleSmall: titleSmall(),
    bodyLarge: bodyLarge(),
    bodyMedium: bodyMedium(),
    bodySmall: bodySmall(),
    labelLarge: labelLarge(),
    labelMedium: labelMedium(),
    labelSmall: labelSmall(),
  );
}
 