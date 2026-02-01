import 'package:flutter/material.dart';
import '../../design/app_colors.dart';
import '../../design/app_spacing.dart';
import '../../design/app_typography.dart';

/// Modern service card for displaying service options
/// Used in dashboards to navigate to different services
class ServiceCard extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final int? customerCount;
  final bool isActive;

  const ServiceCard({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.onTap,
    this.customerCount,
    this.isActive = true,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: AppSpacing.elevationMd,
      shape: RoundedRectangleBorder(
        borderRadius: AppSpacing.borderRadiusLg,
      ),
      child: InkWell(
        onTap: isActive ? onTap : null,
        borderRadius: AppSpacing.borderRadiusLg,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: AppSpacing.borderRadiusLg,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withValues(alpha: 0.1),
                color.withValues(alpha: 0.05),
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon and badge row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: AppSpacing.borderRadiusMd,
                        border: Border.all(
                          color: color.withValues(alpha: 0.3),
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        icon,
                        color: color,
                        size: AppSpacing.iconXl,
                      ),
                    ),
                    if (customerCount != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.sm,
                        ),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: AppSpacing.borderRadiusFull,
                        ),
                        child: Text(
                          customerCount.toString(),
                          style: AppTypography.labelMedium(
                            color: AppColors.white,
                          ),
                        ),
                      ),
                  ],
                ),

                const Spacer(),

                // Title
                Text(
                  title,
                  style: AppTypography.headlineSmall(
                    color: AppColors.textPrimary,
                  ),
                ),

                AppSpacing.vSm,

                // Description
                Text(
                  description,
                  style: AppTypography.bodyMedium(
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),

                AppSpacing.vMd,

                // Action indicator
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (customerCount != null)
                      Text(
                        '$customerCount ${customerCount == 1 ? 'customer' : 'customers'}',
                        style: AppTypography.bodySmall(
                          color: AppColors.textDisabled,
                        ),
                      )
                    else
                      const SizedBox.shrink(),
                    Icon(
                      Icons.arrow_forward,
                      color: color,
                      size: AppSpacing.iconMd,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
