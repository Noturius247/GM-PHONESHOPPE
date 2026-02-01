import 'package:flutter/material.dart';
import '../../design/app_colors.dart';
import '../../design/app_spacing.dart';
import '../../design/app_typography.dart';

/// Reusable stat card for displaying metrics
/// Used in admin and user dashboards
class StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color? color;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool showTrendIndicator;
  final double? trendValue;

  const StatCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    this.color,
    this.subtitle,
    this.onTap,
    this.showTrendIndicator = false,
    this.trendValue,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor = color ?? Theme.of(context).colorScheme.primary;
    final bool isPositiveTrend = (trendValue ?? 0) >= 0;

    return Card(
      elevation: AppSpacing.elevationSm,
      shape: RoundedRectangleBorder(
        borderRadius: AppSpacing.borderRadiusMd,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: AppSpacing.borderRadiusMd,
        child: Container(
          padding: AppSpacing.paddingCard,
          decoration: BoxDecoration(
            borderRadius: AppSpacing.borderRadiusMd,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                cardColor.withValues(alpha: 0.05),
                cardColor.withValues(alpha: 0.01),
              ],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon and trend row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: cardColor.withValues(alpha: 0.1),
                      borderRadius: AppSpacing.borderRadiusMd,
                    ),
                    child: Icon(
                      icon,
                      color: cardColor,
                      size: AppSpacing.iconLg,
                    ),
                  ),
                  if (showTrendIndicator && trendValue != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: (isPositiveTrend ? AppColors.success : AppColors.error)
                            .withValues(alpha: 0.1),
                        borderRadius: AppSpacing.borderRadiusSm,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isPositiveTrend
                                ? Icons.trending_up
                                : Icons.trending_down,
                            size: AppSpacing.iconSm,
                            color: isPositiveTrend
                                ? AppColors.success
                                : AppColors.error,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '${trendValue!.abs().toStringAsFixed(1)}%',
                            style: AppTypography.labelSmall(
                              color: isPositiveTrend
                                  ? AppColors.success
                                  : AppColors.error,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),

              AppSpacing.vLg,

              // Value
              Text(
                value,
                style: AppTypography.displaySmall(color: AppColors.textPrimary),
              ),

              AppSpacing.vXs,

              // Title
              Text(
                title,
                style: AppTypography.bodyMedium(color: AppColors.textSecondary),
              ),

              // Subtitle (optional)
              if (subtitle != null) ...[
                AppSpacing.vXs,
                Text(
                  subtitle!,
                  style: AppTypography.bodySmall(color: AppColors.textDisabled),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
