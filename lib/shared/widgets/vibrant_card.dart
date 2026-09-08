import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import 'avatar_stack.dart';

class VibrantCard extends StatelessWidget {
  final Color backgroundColor;
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

  const VibrantCard({
    super.key,
    required this.backgroundColor,
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
  });

  @override
  Widget build(BuildContext context) {
    final isDarkCard = backgroundColor.computeLuminance() < 0.4;
    final textColor = isDarkCard ? Colors.white : AppColors.textPrimaryLight;
    final subtextColor = isDarkCard ? Colors.white70 : AppColors.textSecondaryLight;

    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(AppSpacing.p20),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(AppSpacing.r28),
        boxShadow: [
          BoxShadow(
            color: backgroundColor.withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Row: Badge & Arrow Button or Trailing
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (badgeText != null)
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: badgeColor ?? (isDarkCard ? Colors.white24 : Colors.white.withValues(alpha: 0.6)),
                      borderRadius: BorderRadius.circular(AppSpacing.rPill),
                    ),
                    child: Text(
                      badgeText!,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDarkCard ? Colors.white : AppColors.textPrimaryLight,
                      ),
                    ),
                  ),
                )
              else
                const SizedBox.shrink(),
              if (trailing != null)
                trailing!
              else if (onArrowTap != null)
                GestureDetector(
                  onTap: onArrowTap,
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: isDarkCard ? Colors.white.withValues(alpha: 0.2) : AppColors.actionCircleDark,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.arrow_outward_rounded,
                      size: 20,
                      color: isDarkCard ? Colors.white : Colors.white,
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: AppSpacing.p16),

          // Title & Subtitle
          Text(
            title,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: textColor,
              letterSpacing: -0.3,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: subtextColor,
              ),
            ),
          ],

          if (customContent != null) ...[
            const SizedBox(height: AppSpacing.p16),
            customContent!,
          ],

          // Bottom Metric & Avatar Stack
          if (metricValue != null || avatarUrls.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.p20),
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
                            fontWeight: FontWeight.w800,
                            color: textColor,
                          ),
                        ),
                        if (metricLabel != null)
                          Text(
                            metricLabel!,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
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
    );
  }
}
