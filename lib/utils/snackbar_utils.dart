import 'package:flutter/material.dart';

/// Utility class for showing SnackBars at the top of the screen
class SnackBarUtils {
  /// Shows a SnackBar at the top of the screen
  static void showTopSnackBar(
    BuildContext context, {
    required String message,
    Color? backgroundColor,
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
    Widget? content,
  }) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    final mediaQuery = MediaQuery.of(context);
    final topPadding = mediaQuery.padding.top;
    final bottomPadding = mediaQuery.padding.bottom;
    final screenHeight = mediaQuery.size.height;
    final screenWidth = mediaQuery.size.width;
    final isLandscape = screenWidth > screenHeight;

    // Calculate bottom margin to position snackbar near the top
    // Adaptive positioning based on orientation
    final topOffset = topPadding + (isLandscape ? 80 : 60); // Less offset in portrait
    final bottomMargin = screenHeight - topOffset - bottomPadding;

    // Clamp to ensure snackbar stays visible
    // Portrait: keep it closer to middle-top (max 60% from bottom)
    // Landscape: allow higher positioning (max 85% from bottom)
    final maxBottomMargin = isLandscape ? screenHeight * 0.85 : screenHeight * 0.60;
    final safeBottomMargin = bottomMargin.clamp(50.0, maxBottomMargin);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: content ?? Text(message),
        backgroundColor: backgroundColor,
        duration: duration,
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(
          bottom: safeBottomMargin,
          left: 16,
          right: 16,
        ),
        action: action,
      ),
    );
  }

  /// Shows a success SnackBar (green) at the top
  static void showSuccess(BuildContext context, String message, {Duration? duration}) {
    showTopSnackBar(
      context,
      message: message,
      backgroundColor: Colors.green,
      duration: duration ?? const Duration(seconds: 2),
    );
  }

  /// Shows an error SnackBar (red) at the top
  static void showError(BuildContext context, String message, {Duration? duration}) {
    showTopSnackBar(
      context,
      message: message,
      backgroundColor: Colors.red,
      duration: duration ?? const Duration(seconds: 3),
    );
  }

  /// Shows a warning SnackBar (orange) at the top
  static void showWarning(BuildContext context, String message, {Duration? duration}) {
    showTopSnackBar(
      context,
      message: message,
      backgroundColor: Colors.orange,
      duration: duration ?? const Duration(seconds: 3),
    );
  }

  /// Shows an info SnackBar (blue) at the top
  static void showInfo(BuildContext context, String message, {Duration? duration}) {
    showTopSnackBar(
      context,
      message: message,
      backgroundColor: const Color(0xFF3498DB),
      duration: duration ?? const Duration(seconds: 2),
    );
  }

  /// Shows e-wallet service added SnackBar with fee details
  static void showEWalletAdded(
    BuildContext context, {
    required String provider, // 'GCash', 'Maya'
    required String type, // 'Cash-In', 'Cash-Out'
    required double sellingPrice,
    required double fee,
    required double actualCashGiven,
    required String feeHandling, // 'fee_included', 'fee_separate', 'auto_deduct'
  }) {
    final feeMsg = feeHandling == 'fee_separate'
        ? ' (₱${fee.toStringAsFixed(2)} to cashier)'
        : feeHandling == 'auto_deduct'
            ? ' (₱${fee.toStringAsFixed(2)} deducted, gives ₱${actualCashGiven.toStringAsFixed(2)})'
            : fee > 0 ? ' (fee included)' : '';

    final color = type == 'Cash-Out'
        ? const Color(0xFFE67E22) // Orange for Cash-Out
        : (provider == 'GCash' ? const Color(0xFF007BFF) : const Color(0xFF2ECC71)); // Blue/Green for Cash-In

    showTopSnackBar(
      context,
      message: 'Added: $provider $type ₱${sellingPrice.toStringAsFixed(2)}$feeMsg',
      backgroundColor: color,
      duration: const Duration(seconds: 3),
    );
  }
}
