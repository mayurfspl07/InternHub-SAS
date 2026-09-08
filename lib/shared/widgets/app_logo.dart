import 'package:flutter/material.dart';

enum AppLogoVariant {
  horizontal,
  mark,
}

/// Global InternHub Logo Component
/// Automatically selects [Logo_lightmode.png] or [logo_darkmode.png] based on theme,
/// or uses [Favicon.png] for mark-only display.
class AppLogo extends StatelessWidget {
  final double? height;
  final double? width;
  final AppLogoVariant variant;
  final bool? isDark;
  final BoxFit fit;

  const AppLogo({
    super.key,
    this.height,
    this.width,
    this.variant = AppLogoVariant.horizontal,
    this.isDark,
    this.fit = BoxFit.contain,
  });

  const AppLogo.mark({
    super.key,
    this.height = 36,
    this.width = 36,
    this.isDark,
    this.fit = BoxFit.contain,
  }) : variant = AppLogoVariant.mark;

  const AppLogo.horizontal({
    super.key,
    this.height = 32,
    this.width,
    this.isDark,
    this.fit = BoxFit.contain,
  }) : variant = AppLogoVariant.horizontal;

  @override
  Widget build(BuildContext context) {
    final effectiveIsDark = isDark ?? (Theme.of(context).brightness == Brightness.dark);

    if (variant == AppLogoVariant.mark) {
      return Image.asset(
        'assets/images/Favicon.png',
        height: height,
        width: width,
        fit: fit,
        errorBuilder: (context, error, stackTrace) => const Icon(Icons.hub_rounded, color: Color(0xFF7C3AED)),
      );
    }

    final assetPath = effectiveIsDark
        ? 'assets/images/logo_darkmode.png'
        : 'assets/images/Logo_lightmode.png';

    return Image.asset(
      assetPath,
      height: height,
      width: width,
      fit: fit,
      errorBuilder: (context, error, stackTrace) => const Text(
        'InternHub',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
      ),
    );
  }
}
