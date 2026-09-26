import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

class AppAvatar extends StatelessWidget {
  final String? url;
  final double size;
  final String? fallbackText;
  final Color? borderColor;
  final double borderWidth;

  const AppAvatar({
    super.key,
    this.url,
    this.size = 40.0,
    this.fallbackText,
    this.borderColor,
    this.borderWidth = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    final hasUrl = url != null && url!.trim().isNotEmpty;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: borderColor != null
            ? Border.all(color: borderColor!, width: borderWidth)
            : null,
      ),
      child: ClipOval(
        child: hasUrl
            ? Image.network(
                url!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => _buildFallback(),
              )
            : _buildFallback(),
      ),
    );
  }

  Widget _buildFallback() {
    return Container(
      color: AppColors.primarySoft,
      child: Center(
        child: Text(
          fallbackText != null && fallbackText!.isNotEmpty
              ? fallbackText![0].toUpperCase()
              : '👤',
          style: TextStyle(
            fontSize: size * 0.45,
            fontWeight: FontWeight.bold,
            color: AppColors.primaryInk,
          ),
        ),
      ),
    );
  }
}
