import 'package:flutter/material.dart';
import '../../core/api/api_config.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';

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
    final resolved = hasUrl ? ApiConfig.mediaUrl(url!) : null;

    final avatar = Container(
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
                resolved!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => _buildFallback(),
                loadingBuilder: (context, child, progress) => progress == null ? child : _buildFallback(),
              )
            : _buildFallback(),
      ),
    );
    final name = fallbackText?.trim() ?? '';
    return Semantics(image: true, label: name.isEmpty ? 'Profile photo' : name, child: ExcludeSemantics(child: avatar));
  }

  Widget _buildFallback() {
    final initial = fallbackText != null && fallbackText!.trim().isNotEmpty ? fallbackText!.trim()[0].toUpperCase() : null;
    return Container(
      color: AppColors.primarySoft,
      child: Center(
        child: initial == null
            ? Icon(Icons.person_rounded, size: size * 0.55, color: AppColors.primaryInk)
            : Text(
                initial,
                style: AppTypography.cardTitle.copyWith(fontSize: size * 0.45, color: AppColors.primaryInk),
              ),
      ),
    );
  }
}
