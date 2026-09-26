import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_typography.dart';

/// Amber hero ("Let's start your day") with an optional sand "peek" card to
/// its right carrying a vertical label ("Evening").
class HeroBannerCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? illustration;
  final Widget? footer;
  final Color color;
  final double height;
  final VoidCallback? onTap;
  final String? peekLabel;
  final VoidCallback? onPeekTap;

  const HeroBannerCard({
    super.key,
    required this.title,
    this.subtitle,
    this.illustration,
    this.footer,
    this.color = AppColors.primary,
    this.height = 210,
    this.onTap,
    this.peekLabel,
    this.onPeekTap,
  });

  @override
  Widget build(BuildContext context) {
    final hero = Material(
      color: color,
      borderRadius: BorderRadius.circular(AppSpacing.rCard),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          child: Column(
            children: [
              Text(title, textAlign: TextAlign.center, style: AppTypography.section),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption.copyWith(color: AppColors.ink.withValues(alpha: 0.7)),
                ),
              ],
              if (illustration != null) Expanded(child: Center(child: illustration)) else const Spacer(),
              ?footer,
            ],
          ),
        ),
      ),
    );

    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: hero),
          if (peekLabel != null) ...[
            const SizedBox(width: 10),
            SizedBox(
              width: 46,
              child: Material(
                color: AppColors.sand,
                borderRadius: BorderRadius.circular(AppSpacing.rTile),
                child: InkWell(
                  onTap: onPeekTap,
                  borderRadius: BorderRadius.circular(AppSpacing.rTile),
                  child: Center(
                    child: RotatedBox(
                      quarterTurns: 1,
                      child: Text(peekLabel!, style: AppTypography.cardTitle.copyWith(fontSize: 14)),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Soft sun-over-hills illustration used inside [HeroBannerCard].
class SunriseIllustration extends StatelessWidget {
  final double size;

  const SunriseIllustration({super.key, this.size = 110});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size * 1.6,
      height: size,
      child: CustomPaint(painter: _SunrisePainter()),
    );
  }
}

class _SunrisePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final sunCenter = Offset(w * 0.5, h * 0.42);
    final r = h * 0.2;

    final rayPaint = Paint()
      ..color = AppColors.sun
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < 12; i++) {
      final angle = i * math.pi * 2 / 12;
      final dir = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(sunCenter + dir * (r + 5), sunCenter + dir * (r + 12), rayPaint);
    }
    canvas.drawCircle(sunCenter, r, Paint()..color = AppColors.sun);

    final back = Path()
      ..moveTo(0, h * 0.78)
      ..quadraticBezierTo(w * 0.3, h * 0.55, w * 0.62, h * 0.72)
      ..quadraticBezierTo(w * 0.85, h * 0.8, w, h * 0.66)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(back, Paint()..color = AppColors.olive.withValues(alpha: 0.75));

    final front = Path()
      ..moveTo(0, h * 0.9)
      ..quadraticBezierTo(w * 0.45, h * 0.72, w, h * 0.88)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(front, Paint()..color = AppColors.hill);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
