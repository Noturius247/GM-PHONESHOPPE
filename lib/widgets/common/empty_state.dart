import 'package:flutter/material.dart';
import '../../design/app_colors.dart';
import '../../design/app_spacing.dart';
import '../../design/app_typography.dart';

/// Empty state widget for when there's no data to display
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Icon
            Container(
              padding: const EdgeInsets.all(AppSpacing.xl),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 64,
                color: AppColors.textDisabled,
              ),
            ),

            AppSpacing.vXl,

            // Title
            Text(
              title,
              style: AppTypography.headlineMedium(
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),

            AppSpacing.vMd,

            // Message
            Text(
              message,
              style: AppTypography.bodyLarge(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),

            // Action button (optional)
            if (actionLabel != null && onAction != null) ...[
              AppSpacing.vXl,
              ElevatedButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.add),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
