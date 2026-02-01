import 'package:flutter/material.dart';
import '../../design/app_colors.dart';
import '../../design/app_spacing.dart';
import '../../design/app_typography.dart';

/// Reusable status badge for displaying active/inactive states
class StatusBadge extends StatelessWidget {
  final String status;
  final bool isActive;
  final Color? activeColor;
  final Color? inactiveColor;

  const StatusBadge({
    super.key,
    required this.status,
    this.isActive = true,
    this.activeColor,
    this.inactiveColor,
  });

  /// Named constructor for active status
  const StatusBadge.active({super.key})
      : status = 'Active',
        isActive = true,
        activeColor = null,
        inactiveColor = null;

  /// Named constructor for inactive status
  const StatusBadge.inactive({super.key})
      : status = 'Inactive',
        isActive = false,
        activeColor = null,
        inactiveColor = null;

  @override
  Widget build(BuildContext context) {
    final Color badgeColor = isActive
        ? (activeColor ?? AppColors.activeGreen)
        : (inactiveColor ?? AppColors.inactiveGray);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.1),
        borderRadius: AppSpacing.borderRadiusSm,
        border: Border.all(
          color: badgeColor.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: badgeColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            status,
            style: AppTypography.labelSmall(color: badgeColor),
          ),
        ],
      ),
    );
  }
}
