import 'package:flutter/material.dart';
import 'app_avatar.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';

class AvatarStack extends StatelessWidget {
  final List<String> avatarUrls;

  /// Names in the same order as [avatarUrls], used for initials when a photo is missing.
  final List<String>? names;
  final double size;
  final int maxDisplay;

  const AvatarStack({
    super.key,
    required this.avatarUrls,
    this.names,
    this.size = 32.0,
    this.maxDisplay = 3,
  });

  @override
  Widget build(BuildContext context) {
    final displayList = avatarUrls.take(maxDisplay).toList();
    final remaining = avatarUrls.length - maxDisplay;

    return SizedBox(
      height: size,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < displayList.length; i++)
            Align(
              widthFactor: 0.68,
              child: AppAvatar(
                url: displayList[i],
                size: size,
                fallbackText: names != null && i < names!.length ? names![i] : null,
                borderColor: AppColors.surface,
                borderWidth: 2,
              ),
            ),
          if (remaining > 0)
            Align(
              widthFactor: 0.68,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: AppColors.ink,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.surface, width: 2),
                ),
                child: Center(
                  child: Text(
                    '+$remaining',
                    style: AppTypography.label.copyWith(color: AppColors.surface, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
