import 'package:flutter/material.dart';
import '../../core/constants/app_typography.dart';

/// Big centered number with a one-line subtitle ("420 / Celebrate what made
/// you smile today").
class MetricHeader extends StatelessWidget {
  final String value;
  final String subtitle;
  final CrossAxisAlignment alignment;

  const MetricHeader({
    super.key,
    required this.value,
    required this.subtitle,
    this.alignment = CrossAxisAlignment.center,
  });

  @override
  Widget build(BuildContext context) {
    final textAlign = alignment == CrossAxisAlignment.center ? TextAlign.center : TextAlign.start;

    return Column(
      crossAxisAlignment: alignment,
      children: [
        Text(value, textAlign: textAlign, style: AppTypography.metric),
        const SizedBox(height: 6),
        Text(subtitle, textAlign: textAlign, style: AppTypography.body),
      ],
    );
  }
}
