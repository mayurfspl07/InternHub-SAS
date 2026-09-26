import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_typography.dart';

class CapsuleBarDatum {
  final String label;

  /// 0..1 fill of the track.
  final double fraction;

  /// Text shown inside the capsule. Defaults to the rounded percentage.
  final String? valueLabel;
  final Color? color;

  const CapsuleBarDatum({
    required this.label,
    required this.fraction,
    this.valueLabel,
    this.color,
  });
}

/// "Emotions"-style chart: tall rounded tracks with a filled capsule rising
/// from the bottom, the value inside it and the label below.
class CapsuleBarChart extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final List<CapsuleBarDatum> data;
  final double barHeight;
  final Widget? trailing;

  const CapsuleBarChart({
    super.key,
    this.title,
    this.subtitle,
    required this.data,
    this.barHeight = 170,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.rCard),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Row(
              children: [
                Expanded(child: Text(title!, style: AppTypography.section)),
                ?trailing,
              ],
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(subtitle!, style: AppTypography.caption),
            ],
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(),
            ),
          ],
          SizedBox(
            height: barHeight + 26,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (int i = 0; i < data.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(child: _buildBar(data[i], i)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBar(CapsuleBarDatum d, int index) {
    final color = d.color ?? AppColors.chartPalette[index % AppColors.chartPalette.length];
    final fraction = d.fraction.clamp(0.0, 1.0);
    final label = d.valueLabel ?? '${(fraction * 100).round()}%';
    final onColor = color.computeLuminance() > 0.45 ? AppColors.ink : Colors.white;

    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final double fillHeight = (constraints.maxHeight * fraction).clamp(math.min(36.0, constraints.maxWidth), constraints.maxHeight).toDouble();
              return Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(AppSpacing.rPill),
                ),
                alignment: Alignment.bottomCenter,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: fraction == 0 ? 0 : fillHeight),
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOutCubic,
                  builder: (context, h, _) => Container(
                    height: h,
                    width: double.infinity,
                    alignment: Alignment.bottomCenter,
                    padding: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(AppSpacing.rPill),
                    ),
                    child: h > 28
                        ? FittedBox(
                            child: Text(label, style: AppTypography.label.copyWith(color: onColor)),
                          )
                        : null,
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Text(
          d.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.caption.copyWith(color: AppColors.ink),
        ),
      ],
    );
  }
}
