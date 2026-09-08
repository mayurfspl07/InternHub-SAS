import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

class SegmentedProgressBar extends StatelessWidget {
  final int totalSegments;
  final int completedSegments;
  final double percentage;
  final Color activeColor;
  final Color inactiveColor;

  const SegmentedProgressBar({
    super.key,
    this.totalSegments = 5,
    required this.completedSegments,
    required this.percentage,
    this.activeColor = AppColors.primary,
    this.inactiveColor = const Color(0xFFE5E7EB),
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.borderLight,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Center(
                        child: Text('🚀', style: TextStyle(fontSize: 16)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Your progress now',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : AppColors.textPrimaryLight,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${(percentage * 100).toInt()}%',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : AppColors.textPrimaryLight,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Multi-segment Bar
          Row(
            children: [
              for (int i = 0; i < totalSegments; i++) ...[
                Expanded(
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: i < completedSegments ? activeColor : (isDark ? const Color(0xFF2D3243) : inactiveColor),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                if (i < totalSegments - 1) const SizedBox(width: 6),
              ],
            ],
          ),

          const SizedBox(height: 12),
          Text(
            '$completedSegments/$totalSegments Task Complete',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white60 : AppColors.textSecondaryLight,
            ),
          ),
        ],
      ),
    );
  }
}
