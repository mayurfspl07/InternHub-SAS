import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

class StarRating extends StatelessWidget {
  final int rating;
  final int maxRating;
  final ValueChanged<int>? onRatingChanged;
  final double size;
  final Color activeColor;
  final Color inactiveColor;

  const StarRating({
    super.key,
    required this.rating,
    this.maxRating = 5,
    this.onRatingChanged,
    this.size = 28,
    this.activeColor = AppColors.warning, // Amber yellow
    this.inactiveColor = AppColors.border, // Light slate
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(maxRating, (index) {
        final starValue = index + 1;
        final isFilled = starValue <= rating;

        return InkWell(
          onTap: onRatingChanged != null ? () => onRatingChanged!(starValue) : null,
          borderRadius: BorderRadius.circular(size / 2),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Icon(
              isFilled ? Icons.star_rounded : Icons.star_outline_rounded,
              color: isFilled ? activeColor : inactiveColor,
              size: size,
            ),
          ),
        );
      }),
    );
  }
}
