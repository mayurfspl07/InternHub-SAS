import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';

enum AppLogoVariant {
  horizontal,
  mark,
}

/// Global InternHub logo: [Logo_lightmode.png] for the horizontal lockup,
/// [Favicon.png] for mark-only display.
class AppLogo extends StatelessWidget {
  final double? height;
  final double? width;
  final AppLogoVariant variant;
  final BoxFit fit;

  const AppLogo({
    super.key,
    this.height,
    this.width,
    this.variant = AppLogoVariant.horizontal,
    this.fit = BoxFit.contain,
  });

  const AppLogo.mark({
    super.key,
    this.height = 36,
    this.width = 36,
    this.fit = BoxFit.contain,
  }) : variant = AppLogoVariant.mark;

  const AppLogo.horizontal({
    super.key,
    this.height = 32,
    this.width,
    this.fit = BoxFit.contain,
  }) : variant = AppLogoVariant.horizontal;

  @override
  Widget build(BuildContext context) {
    if (variant == AppLogoVariant.mark) {
      return Image.asset(
        'assets/images/Favicon.png',
        height: height,
        width: width,
        fit: fit,
        errorBuilder: (context, error, stackTrace) => const Icon(Icons.hub_rounded, color: AppColors.primaryInk),
      );
    }

    return Image.asset(
      'assets/images/Logo_lightmode.png',
      height: height,
      width: width,
      fit: fit,
      errorBuilder: (context, error, stackTrace) => Text('InternHub', style: AppTypography.section),
    );
  }
}
