import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_typography.dart';

/// White pill with tinted text ("Personal", "Calm", "Motivation").
class AppTag extends StatelessWidget {
  final String label;
  final Color color;
  final Color background;
  final IconData? icon;

  const AppTag({
    super.key,
    required this.label,
    this.color = AppColors.ink,
    this.background = AppColors.surface,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppSpacing.rPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.label.copyWith(color: color, fontSize: 11.5),
            ),
          ),
        ],
      ),
    );
  }
}
