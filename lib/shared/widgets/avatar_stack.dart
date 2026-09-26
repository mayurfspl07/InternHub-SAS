import 'package:flutter/material.dart';
import 'app_avatar.dart';
import '../../core/constants/app_colors.dart';

class AvatarStack extends StatelessWidget {
  final List<String> avatarUrls;
  final double size;
  final int maxDisplay;

  const AvatarStack({
    super.key,
    required this.avatarUrls,
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
                borderColor: Colors.white,
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
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Center(
                  child: Text(
                    '+$remaining',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
