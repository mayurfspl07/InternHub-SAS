import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_typography.dart';
import 'app_tag.dart';

/// Pastel background plus the ink used for its tag and icon.
class PastelTone {
  final Color background;
  final Color ink;

  const PastelTone(this.background, this.ink);

  static const peach = PastelTone(AppColors.peach, AppColors.peachInk);
  static const lavender = PastelTone(AppColors.lavender, AppColors.lavenderInk);
  static const butter = PastelTone(AppColors.butter, AppColors.butterInk);
  static const sage = PastelTone(AppColors.sage, AppColors.sageInk);
  static const sand = PastelTone(AppColors.sand, AppColors.ink);

  static const cycle = [peach, lavender, butter, sage, sand];
}

/// "Quick Journal" card: pastel background, title (optionally with an icon),
/// a prompt line, and a footer with a caption and a white tag.
class PastelCard extends StatelessWidget {
  final String title;
  final String? body;
  final String? footer;
  final String? tag;
  final IconData? icon;
  final PastelTone tone;
  final double width;
  final double? height;
  final VoidCallback? onTap;

  const PastelCard({
    super.key,
    required this.title,
    this.body,
    this.footer,
    this.tag,
    this.icon,
    this.tone = PastelTone.peach,
    this.width = 170,
    this.height,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Material(
        color: tone.background,
        borderRadius: BorderRadius.circular(AppSpacing.rTile),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.rTile),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.cardTitle.copyWith(fontSize: 14)),
                    ),
                    if (icon != null) ...[
                      const SizedBox(width: 4),
                      Icon(icon, size: 15, color: tone.ink),
                    ],
                  ],
                ),
                if (body != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    body!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption.copyWith(color: AppColors.ink.withValues(alpha: 0.7)),
                  ),
                ],
                // Push the footer to the bottom when the card has a fixed height; otherwise a Spacer would throw.
                if (height != null) const Spacer() else const SizedBox(height: 12),
                if (footer != null || tag != null)
                  Row(
                    children: [
                      if (footer != null)
                        Expanded(
                          child: Text(
                            footer!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.label.copyWith(color: AppColors.ink.withValues(alpha: 0.6), fontWeight: FontWeight.w500),
                          ),
                        )
                      else
                        const Spacer(),
                      if (tag != null) AppTag(label: tag!, color: tone.ink),
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
