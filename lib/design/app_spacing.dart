import 'package:flutter/material.dart';

/// Centralized spacing constants for consistent layouts
class AppSpacing {
  // Base spacing unit (8px)
  static const double unit = 8.0;

  // Spacing Scale
  static const double xs = 4.0;   // 0.5x
  static const double sm = 8.0;   // 1x
  static const double md = 16.0;  // 2x
  static const double lg = 24.0;  // 3x
  static const double xl = 32.0;  // 4x
  static const double xxl = 40.0; // 5x
  static const double xxxl = 48.0; // 6x

  // Component-specific spacing
  static const double cardPadding = 20.0;
  static const double pagePadding = 24.0;
  static const double sectionSpacing = 32.0;
  static const double itemSpacing = 12.0;

  // Border Radius
  static const double radiusXs = 4.0;
  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0;
  static const double radiusLg = 16.0;
  static const double radiusXl = 24.0;
  static const double radiusFull = 9999.0; // Fully rounded

  // Elevation
  static const double elevationNone = 0.0;
  static const double elevationXs = 1.0;
  static const double elevationSm = 2.0;
  static const double elevationMd = 4.0;
  static const double elevationLg = 8.0;
  static const double elevationXl = 16.0;

  // Icon Sizes
  static const double iconXs = 16.0;
  static const double iconSm = 20.0;
  static const double iconMd = 24.0;
  static const double iconLg = 32.0;
  static const double iconXl = 48.0;

  // Avatar Sizes
  static const double avatarSm = 32.0;
  static const double avatarMd = 40.0;
  static const double avatarLg = 56.0;
  static const double avatarXl = 80.0;

  // Button Heights
  static const double buttonSm = 36.0;
  static const double buttonMd = 48.0;
  static const double buttonLg = 56.0;

  // Breakpoints for responsive design
  static const double breakpointMobile = 600.0;
  static const double breakpointTablet = 900.0;
  static const double breakpointDesktop = 1200.0;

  // Helper methods for SizedBox
  static SizedBox get hXs => const SizedBox(width: xs);
  static SizedBox get hSm => const SizedBox(width: sm);
  static SizedBox get hMd => const SizedBox(width: md);
  static SizedBox get hLg => const SizedBox(width: lg);
  static SizedBox get hXl => const SizedBox(width: xl);

  static SizedBox get vXs => const SizedBox(height: xs);
  static SizedBox get vSm => const SizedBox(height: sm);
  static SizedBox get vMd => const SizedBox(height: md);
  static SizedBox get vLg => const SizedBox(height: lg);
  static SizedBox get vXl => const SizedBox(height: xl);
  static SizedBox get vXxl => const SizedBox(height: xxl);

  // EdgeInsets helpers
  static EdgeInsets get paddingXs => const EdgeInsets.all(xs);
  static EdgeInsets get paddingSm => const EdgeInsets.all(sm);
  static EdgeInsets get paddingMd => const EdgeInsets.all(md);
  static EdgeInsets get paddingLg => const EdgeInsets.all(lg);
  static EdgeInsets get paddingXl => const EdgeInsets.all(xl);

  static EdgeInsets get paddingCard => const EdgeInsets.all(cardPadding);
  static EdgeInsets get paddingPage => const EdgeInsets.all(pagePadding);

  // Border Radius helpers
  static BorderRadius get borderRadiusXs => BorderRadius.circular(radiusXs);
  static BorderRadius get borderRadiusSm => BorderRadius.circular(radiusSm);
  static BorderRadius get borderRadiusMd => BorderRadius.circular(radiusMd);
  static BorderRadius get borderRadiusLg => BorderRadius.circular(radiusLg);
  static BorderRadius get borderRadiusXl => BorderRadius.circular(radiusXl);
  static BorderRadius get borderRadiusFull => BorderRadius.circular(radiusFull);
}
