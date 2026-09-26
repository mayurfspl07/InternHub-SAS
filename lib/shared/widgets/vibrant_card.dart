import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_typography.dart';
import 'avatar_stack.dart';

class VibrantCard extends StatelessWidget {
  final Color? backgroundColor;
  final String? badgeText;
  final Color? badgeColor;
  final String title;
  final String? subtitle;
  final String? metricValue;
  final String? metricLabel;
  final List<String> avatarUrls;
  final VoidCallback? onArrowTap;
  final Widget? trailing;
  final Widget? customContent;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;
  final Border? border;

  const VibrantCard({
    super.key,
    this.backgroundColor,
    this.badgeText,
    this.badgeColor,
    required this.title,
    this.subtitle,
    this.metricValue,
    this.metricLabel,
    this.avatarUrls = const [],
    this.onArrowTap,
    this.trailing,
    this.customContent,
    this.padding,
    this.borderRadius = AppSpacing.r24,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedBg = backgroundColor ?? AppColors.surface;
    // Determine text colors based on background luminance if custom color provided
    final isCardLight = resolvedBg.computeLuminance() > 0.5;
    final textColor = isCardLight ? AppColors.ink : Colors.white;
    final subtextColor = isCardLight ? AppColors.textSecondary : Colors.white70;

    return Container(
      decoration: BoxDecoration(
        color: resolvedBg,
        borderRadius: BorderRadius.circular(borderRadius),
        border: border,
        boxShadow: resolvedBg == AppColors.surface ? AppShadows.soft : AppShadows.none,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(borderRadius),
        child: InkWell(
          onTap: onArrowTap,
          borderRadius: BorderRadius.circular(borderRadius),
          child: Padding(
            padding: padding ?? const EdgeInsets.all(AppSpacing.p20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top Row: Badge & Action
                if (badgeText != null || trailing != null || onArrowTap != null) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (badgeText != null)
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: badgeColor ??
                                  (isCardLight ? AppColors.primarySoft : Colors.white.withValues(alpha: 0.18)),
                              borderRadius: BorderRadius.circular(AppSpacing.rPill),
                            ),
                            child: Text(
                              badgeText!,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: badgeColor != null ? Colors.white : (isCardLight ? AppColors.primaryInk : Colors.white),
                              ),
                            ),
                          ),
                        )
                      else
                        const SizedBox.shrink(),
                      if (trailing != null)
                        trailing!
                      else if (onArrowTap != null)
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: isCardLight ? AppColors.surface : Colors.white.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.arrow_forward_rounded,
                            size: 18,
                            color: isCardLight ? AppColors.ink : Colors.white,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.p12),
                ],

                // Title & Subtitle
                Text(
                  title,
                  style: AppTypography.section.copyWith(
                    color: textColor,
                    fontSize: 18,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: AppTypography.body.copyWith(
                      color: subtextColor,
                      fontSize: 13,
                    ),
                  ),
                ],

                if (customContent != null) ...[
                  const SizedBox(height: AppSpacing.p12),
                  customContent!,
                ],

                // Bottom Metric & Avatar Stack
                if (metricValue != null || avatarUrls.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.p16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (metricValue != null)
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                metricValue!,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color: textColor,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              if (metricLabel != null)
                                Text(
                                  metricLabel!,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: subtextColor,
                                  ),
                                ),
                            ],
                          ),
                        )
                      else
                        const SizedBox.shrink(),
                      if (avatarUrls.isNotEmpty)
                        AvatarStack(avatarUrls: avatarUrls),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
