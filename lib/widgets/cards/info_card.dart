import 'package:flutter/material.dart';
import '../../design/app_colors.dart';
import '../../design/app_spacing.dart';
import '../../design/app_typography.dart';

/// Reusable info card displaying customer information
/// Used across all service pages (Cignal, Satlite, GSAT, Sky)
class InfoCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String status;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onTap;
  final Color? accentColor;

  const InfoCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.status,
    this.onEdit,
    this.onDelete,
    this.onTap,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final bool isActive = status.toLowerCase() == 'active';
    final Color statusColor = isActive ? AppColors.activeGreen : AppColors.inactiveGray;
    final Color cardAccent = accentColor ?? Theme.of(context).colorScheme.primary;

    return Card(
      elevation: AppSpacing.elevationSm,
      shape: RoundedRectangleBorder(
        borderRadius: AppSpacing.borderRadiusMd,
        side: BorderSide(
          color: cardAccent.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: AppSpacing.borderRadiusMd,
        child: Padding(
          padding: AppSpacing.paddingCard,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with title and status
              Row(
                children: [
                  // Accent indicator
                  Container(
                    width: 4,
                    height: 40,
                    decoration: BoxDecoration(
                      color: cardAccent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  AppSpacing.hMd,

                  // Title and subtitle
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: AppTypography.titleMedium(
                            color: AppColors.textPrimary,
                          ),
                        ),
                        AppSpacing.vXs,
                        Text(
                          subtitle,
                          style: AppTypography.bodySmall(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Status badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: AppSpacing.borderRadiusSm,
                      border: Border.all(
                        color: statusColor.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      status,
                      style: AppTypography.labelSmall(color: statusColor),
                    ),
                  ),
                ],
              ),

              // Actions row (if provided)
              if (onEdit != null || onDelete != null) ...[
                AppSpacing.vMd,
                const Divider(height: 1),
                AppSpacing.vSm,
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (onEdit != null)
                      TextButton.icon(
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit_outlined, size: AppSpacing.iconSm),
                        label: Text('Edit', style: AppTypography.labelMedium()),
                        style: TextButton.styleFrom(
                          foregroundColor: cardAccent,
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.sm,
                          ),
                        ),
                      ),
                    if (onEdit != null && onDelete != null) AppSpacing.hSm,
                    if (onDelete != null)
                      TextButton.icon(
                        onPressed: onDelete,
                        icon: const Icon(Icons.delete_outline, size: AppSpacing.iconSm),
                        label: Text('Delete', style: AppTypography.labelMedium()),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.error,
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.sm,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
