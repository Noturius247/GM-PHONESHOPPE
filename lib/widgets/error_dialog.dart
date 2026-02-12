import 'package:flutter/material.dart';

/// A reusable error dialog that appears on top of all other content.
/// Use this instead of SnackBars for important error messages that
/// should not be missed by the user.
class ErrorDialog {
  /// Show an error dialog with a title and message.
  ///
  /// [context] - The BuildContext to show the dialog in
  /// [title] - The error title (e.g., "Duplicate Entry")
  /// [message] - The detailed error message
  /// [buttonText] - Optional custom button text (defaults to "OK")
  static Future<void> show({
    required BuildContext context,
    required String title,
    required String message,
    String buttonText = 'OK',
  }) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.error_outline, color: Colors.red, size: 28),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.black87,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(color: Colors.black87, fontSize: 15),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: Text(buttonText),
          ),
        ],
      ),
    );
  }

  /// Show a duplicate entry error dialog.
  ///
  /// [context] - The BuildContext to show the dialog in
  /// [fieldName] - The name of the duplicate field (e.g., "Serial Number", "CCA Number")
  /// [existingCustomerName] - Optional name of the customer who already has this value
  static Future<void> showDuplicate({
    required BuildContext context,
    required String fieldName,
    String? existingCustomerName,
  }) async {
    String message = 'An entry with this $fieldName already exists!';
    if (existingCustomerName != null && existingCustomerName.isNotEmpty) {
      message += '\n\nExisting customer: $existingCustomerName';
    }
    message += '\n\nPlease use a different $fieldName.';

    await show(
      context: context,
      title: 'Duplicate $fieldName',
      message: message,
    );
  }

  /// Show a save failure error dialog.
  static Future<void> showSaveError({
    required BuildContext context,
    String? customMessage,
  }) async {
    await show(
      context: context,
      title: 'Failed to Save',
      message: customMessage ??
          'Unable to save to the database.\n\nPlease check your internet connection and try again.',
    );
  }
}
