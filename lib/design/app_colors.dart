import 'package:flutter/material.dart';

/// Centralized color palette for GM PhoneShoppe
class AppColors {
  // Primary Brand Colors
  static const Color primary = Color(0xFF2196F3);
  static const Color primaryDark = Color(0xFF1976D2);
  static const Color primaryLight = Color(0xFF64B5F6);

  // Landing Page Brand
  static const Color brandBurgundy = Color(0xFF8B1A1A);
  static const Color brandRed = Color(0xFFCC3333);
  static const Color brandRedLight = Color(0xFFE57373);

  // Service Colors
  static const Color cignal = Color(0xFF2196F3); // Blue
  static const Color satlite = Color(0xFF4CAF50); // Green
  static const Color gsat = Color(0xFFFF9800); // Orange
  static const Color sky = Color(0xFF9C27B0); // Purple

  // Service Color Shades
  static const Color cignalLight = Color(0xFF64B5F6);
  static const Color satliteLight = Color(0xFF81C784);
  static const Color gsatLight = Color(0xFFFFB74D);
  static const Color skyLight = Color(0xFFBA68C8);

  static const Color cignalDark = Color(0xFF1976D2);
  static const Color satliteDark = Color(0xFF388E3C);
  static const Color gsatDark = Color(0xFFF57C00);
  static const Color skyDark = Color(0xFF7B1FA2);

  // Neutral Colors
  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF000000);
  static const Color background = Color(0xFFF5F5F5);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFF5F5F5);

  // Text Colors
  static const Color textPrimary = Color(0xFF212121);
  static const Color textSecondary = Color(0xFF757575);
  static const Color textDisabled = Color(0xFFBDBDBD);
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  // Status Colors
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFF9800);
  static const Color error = Color(0xFFF44336);
  static const Color info = Color(0xFF2196F3);

  // Active/Inactive Badge Colors
  static const Color activeGreen = Color(0xFF4CAF50);
  static const Color inactiveGray = Color(0xFF9E9E9E);

  // Border Colors
  static const Color border = Color(0xFFE0E0E0);
  static const Color borderDark = Color(0xFFBDBDBD);

  // Overlay Colors
  static const Color overlay = Color(0x4D000000); // 30% black
  static const Color overlayLight = Color(0x1A000000); // 10% black

  // Dark Mode Colors
  static const Color darkBackground = Color(0xFF121212);
  static const Color darkSurface = Color(0xFF1E1E1E);
  static const Color darkSurfaceVariant = Color(0xFF2C2C2C);

  // Gradient Presets
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, primaryDark],
  );

  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [brandBurgundy, brandRed],
  );

  static LinearGradient serviceGradient(Color serviceColor) {
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        serviceColor,
        serviceColor.withValues(alpha: 0.7),
      ],
    );
  }

  // Helper method to get service color by name
  static Color getServiceColor(String serviceName) {
    switch (serviceName.toLowerCase()) {
      case 'cignal':
        return cignal;
      case 'satlite':
        return satlite;
      case 'gsat':
        return gsat;
      case 'sky':
        return sky;
      default:
        return primary;
    }
  }

  // Helper method to get light variant
  static Color getServiceColorLight(String serviceName) {
    switch (serviceName.toLowerCase()) {
      case 'cignal':
        return cignalLight;
      case 'satlite':
        return satliteLight;
      case 'gsat':
        return gsatLight;
      case 'sky':
        return skyLight;
      default:
        return primaryLight;
    }
  }

  // Helper method to get dark variant
  static Color getServiceColorDark(String serviceName) {
    switch (serviceName.toLowerCase()) {
      case 'cignal':
        return cignalDark;
      case 'satlite':
        return satliteDark;
      case 'gsat':
        return gsatDark;
      case 'sky':
        return skyDark;
      default:
        return primaryDark;
    }
  }
}
