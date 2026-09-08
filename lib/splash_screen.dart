import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'core/api/auth_storage.dart';
import 'features/auth/login_screen.dart';
import 'features/dashboard/main_navigation_wrapper.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _mainController;
  late AnimationController _particleController;

  // The 5 Feature Icons from the Animation Script Storyboard
  final List<Map<String, dynamic>> _features = const [
    {
      'icon': Icons.people_alt_rounded,
      'label': 'People',
      'color': Color(0xFF9333EA), // Purple
      'glow': Color(0xFFA855F7),
    },
    {
      'icon': Icons.assignment_turned_in_rounded,
      'label': 'Tasks',
      'color': Color(0xFFFFD600), // Yellow
      'glow': Color(0xFFFDE047),
    },
    {
      'icon': Icons.bar_chart_rounded,
      'label': 'Analytics',
      'color': Color(0xFFF43F5E), // Pink
      'glow': Color(0xFFFB7185),
    },
    {
      'icon': Icons.calendar_month_rounded,
      'label': 'Calendar',
      'color': Color(0xFF38BDF8), // Blue
      'glow': Color(0xFF7DD3FC),
    },
    {
      'icon': Icons.chat_bubble_rounded,
      'label': 'Messages',
      'color': Color(0xFF34D399), // Mint Green
      'glow': Color(0xFF6EE7B7),
    },
  ];

  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();

    // Exactly 4.8 seconds total duration matching the 4-step storyboard prompt
    _mainController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4800),
    );

    // Continuous floating particle physics
    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();

    _mainController.forward();

    _mainController.addStatusListener((status) async {
      if (status == AnimationStatus.completed && !_hasNavigated) {
        _hasNavigated = true;
        if (mounted) {
          final token = await AuthStorage.getToken();
          if (!mounted) return;
          final targetPage = (token != null && token.isNotEmpty)
              ? const MainNavigationWrapper()
              : const LoginScreen();

          Navigator.of(context).pushReplacement(
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) => targetPage,
              transitionsBuilder:
                  (context, animation, secondaryAnimation, child) {
                    return FadeTransition(
                      opacity: CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeInOutCubic,
                      ),
                      child: child,
                    );
                  },
              transitionDuration: const Duration(milliseconds: 700),
            ),
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _mainController.dispose();
    _particleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    if (size.width <= 0 || size.height <= 0) {
      return const Scaffold(backgroundColor: Color(0xFF07050E));
    }

    return Scaffold(
      backgroundColor: const Color(0xFF07050E),
      body: AnimatedBuilder(
        animation: Listenable.merge([_mainController, _particleController]),
        builder: (context, child) {
          final progress = _mainController.value;

          // ===================================================================
          // STEP 1: PULSE & GLOW (0.0s - 0.8s | progress 0.0 -> 0.167)
          // ===================================================================
          final step1T = (progress / 0.167).clamp(0.0, 1.0);
          final step1LogoScale = step1T < 0.65
              ? Tween<double>(begin: 0.8, end: 1.12)
                    .chain(CurveTween(curve: Curves.easeOutBack))
                    .transform(step1T / 0.65)
              : Tween<double>(begin: 1.12, end: 1.0)
                    .chain(CurveTween(curve: Curves.easeInOut))
                    .transform((step1T - 0.65) / 0.35);

          final step1LogoOpacity = Curves.easeIn.transform(
            (progress / 0.10).clamp(0.0, 1.0),
          );
          final step1RippleProgress = (progress / 0.22).clamp(0.0, 1.0);

          // ===================================================================
          // STEP 2: RISE & BUILD (0.8s - 2.0s | progress 0.167 -> 0.417)
          // ===================================================================
          final step2T = ((progress - 0.167) / 0.250).clamp(0.0, 1.0);
          final lightBeamOpacity = step2T < 0.4
              ? (step2T / 0.4)
              : (1.0 - ((step2T - 0.4) / 0.6)).clamp(0.0, 1.0);

          // Logo lifts up slightly during Step 2 & 3
          final logoYOffset =
              -34.0 *
              Curves.easeInOutCubic.transform(
                progress < 0.167
                    ? 0.0
                    : progress < 0.38
                    ? ((progress - 0.167) / 0.213).clamp(0.0, 1.0)
                    : progress < 0.73
                    ? 1.0
                    : (1.0 - ((progress - 0.73) / 0.10)).clamp(0.0, 1.0),
              );

          // ===================================================================
          // STEP 3: CONNECT & ORBIT (2.0s - 3.5s | progress 0.417 -> 0.729)
          // ===================================================================
          final step3T = ((progress - 0.417) / 0.312).clamp(0.0, 1.0);
          final orbitAngle = (progress - 0.417) * 2.8 * math.pi;

          // ===================================================================
          // STEP 4: SETTLE & LAUNCH (3.5s - 4.8s | progress 0.729 -> 1.0)
          // ===================================================================
          final settleProgress = ((progress - 0.729) / 0.15).clamp(0.0, 1.0);

          // Final State: Progress Bar animates 0% -> 100%
          final progressBarProgress = Curves.easeInOutCubic.transform(
            ((progress - 0.66) / 0.30).clamp(0.0, 1.0),
          );

          // Subtitle switches after Step 2
          final isStep3OrLater = progress >= 0.417;

          return Stack(
            alignment: Alignment.center,
            children: [
              // 1. Background: Deep Purple to Obsidian Black Radial Gradient
              Container(
                width: double.infinity,
                height: double.infinity,
                decoration: const BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0, -0.15),
                    radius: 1.35,
                    colors: [
                      Color(0xFF24104B), // Vibrant deep purple core
                      Color(0xFF13092A), // Mid dark violet
                      Color(0xFF070410), // Deep obsidian black edges
                    ],
                    stops: [0.0, 0.48, 1.0],
                  ),
                ),
              ),

              // 2. Subtle Background Glowing Floating Particles with Parallax
              CustomPaint(
                size: size,
                painter: StoryboardParticlePainter(
                  particleProgress: _particleController.value,
                  speedMultiplier: isStep3OrLater ? 1.5 : 1.0,
                ),
              ),

              // 3. Step 2 Light Beam Rising from Bottom Center Floor Portal
              if (lightBeamOpacity > 0.005)
                CustomPaint(
                  size: size,
                  painter: RadiantFloorBeamPainter(
                    opacity: lightBeamOpacity,
                    beamProgress: step2T,
                  ),
                ),

              // 4. Step 1 Concentric Ripple Circles & Step 3 Dotted Orbital Path & Glowing Circle
              CustomPaint(
                size: size,
                painter: RippleAndOrbitCustomPainter(
                  rippleProgress: step1RippleProgress,
                  step3Progress: step3T,
                  settleProgress: settleProgress,
                  orbitRadius: 122.0,
                  logoYOffset: logoYOffset,
                  orbitAngle: orbitAngle,
                ),
              ),

              // 5. Central InternHub Logo (Pulse, Glow, Rise & Settle)
              Transform.translate(
                offset: Offset(0, logoYOffset),
                child: Opacity(
                  opacity: step1LogoOpacity,
                  child: Transform.scale(
                    scale:
                        step1LogoScale *
                        (settleProgress > 0.1 && settleProgress < 0.8
                            ? (1.0 + 0.08 * math.sin(settleProgress * math.pi))
                            : 1.0),
                    child: _buildInternHubLogo(),
                  ),
                ),
              ),

              // 6. Feature Icons (Rise from floor beam in Step 2 -> Orbit in Step 3 -> Settle in Step 4)
              if (progress > 0.167 && progress < 0.88)
                ..._buildFeatureIcons(
                  progress: progress,
                  step2T: step2T,
                  step3T: step3T,
                  settleProgress: settleProgress,
                  orbitAngle: orbitAngle,
                  logoYOffset: logoYOffset,
                  screenSize: size,
                ),

              // 7. Brand Name & Animated Tagline
              Positioned(
                bottom: size.height * 0.145,
                left: 24,
                right: 24,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Brand Title: InternHub
                    Opacity(
                      opacity: math.min(1.0, progress / 0.14),
                      child: RichText(
                        text: TextSpan(
                          style: GoogleFonts.outfit(
                            fontSize: 36,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                          children: const [
                            TextSpan(
                              text: 'Intern',
                              style: TextStyle(
                                color: Colors.white,
                                shadows: [
                                  Shadow(
                                    color: Color(0xFF9333EA),
                                    blurRadius: 20,
                                  ),
                                ],
                              ),
                            ),
                            TextSpan(
                              text: 'Hub',
                              style: TextStyle(
                                color: Color(0xFFFFD600), // Sunshine Yellow
                                shadows: [
                                  Shadow(
                                    color: Color(0xFFFFD600),
                                    blurRadius: 20,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Tagline transition: Step 1 vs Step 3/4
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 600),
                      switchInCurve: Curves.easeIn,
                      switchOutCurve: Curves.easeOut,
                      child: Text(
                        isStep3OrLater
                            ? 'Manage. Track. Grow.\nAll in One Place.'
                            : 'Where Interns Grow,\nTeams Achieve.',
                        key: ValueKey<bool>(isStep3OrLater),
                        textAlign: TextAlign.center,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.75),
                          height: 1.35,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 8. Final State: Progress Bar & "Getting things ready..."
              if (progress > 0.62)
                Positioned(
                  bottom: size.height * 0.055,
                  left: 48,
                  right: 48,
                  child: Opacity(
                    opacity: ((progress - 0.62) / 0.12).clamp(0.0, 1.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Gradient Progress Bar (0% -> 100%)
                        Container(
                          height: 4.5,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: progressBarProgress,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF8B5CF6),
                                    Color(0xFFC084FC),
                                    Color(0xFFFFD600),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0xFFA855F7),
                                    blurRadius: 10,
                                    spreadRadius: 1,
                                  ),
                                  BoxShadow(
                                    color: Color(0xFFFFD600),
                                    blurRadius: 8,
                                    spreadRadius: 0,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Loading text with cycling animated dots
                        Text(
                          'Getting things ready${'.' * (((progress * 14).toInt() % 3) + 1)}',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.65),
                            letterSpacing: 0.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// High-Fidelity 3D Glowing Logo Matching Storyboard (Purple H + Golden Yellow Dot)
  Widget _buildInternHubLogo() {
    return Container(
      width: 136,
      height: 136,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B5CF6).withValues(alpha: 0.55),
            blurRadius: 40,
            spreadRadius: 10,
          ),
          BoxShadow(
            color: const Color(0xFFFFD600).withValues(alpha: 0.35),
            blurRadius: 24,
            spreadRadius: -2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(38),
        child: Image.asset(
          'assets/images/Favicon.png',
          width: 136,
          height: 136,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            // High-fidelity Custom Vector Fallback
            return Container(
              width: 136,
              height: 136,
              decoration: BoxDecoration(
                color: const Color(0xFF140D2B),
                borderRadius: BorderRadius.circular(38),
                border: Border.all(color: const Color(0xFFA855F7), width: 2.5),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Top Golden Yellow Talent Sphere
                  Positioned(
                    top: 26,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFFFFD600),
                        boxShadow: [
                          BoxShadow(
                            color: Color(0xFFFFD600),
                            blurRadius: 14,
                            spreadRadius: 3,
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Stylized Hub Letter Icon
                  const Positioned(
                    bottom: 22,
                    child: Icon(
                      Icons.hub_rounded,
                      size: 64,
                      color: Color(0xFFC084FC),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// Builds the 5 Orbiting Feature Icons with Step 2, Step 3, and Step 4 Motion Physics
  List<Widget> _buildFeatureIcons({
    required double progress,
    required double step2T,
    required double step3T,
    required double settleProgress,
    required double orbitAngle,
    required double logoYOffset,
    required Size screenSize,
  }) {
    final widgets = <Widget>[];
    const orbitRadius = 122.0;

    // Floor beam origin (where icons emerge in Step 2)
    final floorOriginY = screenSize.height * 0.26;

    for (int i = 0; i < _features.length; i++) {
      final feat = _features[i];

      // Circular Target Position
      final targetAngle = (i * 2 * math.pi / _features.length) - (math.pi / 2);
      final currentAngle = (progress >= 0.417)
          ? targetAngle + orbitAngle
          : targetAngle;

      final targetOrbitX = orbitRadius * math.cos(currentAngle);
      final targetOrbitY = (orbitRadius * math.sin(currentAngle)) + logoYOffset;

      double x;
      double y;
      double scale;
      double opacity;
      double rotation;

      if (progress < 0.417) {
        // STEP 2: RISE & BUILD (Icons emerge from floor beam and fan out)
        final iconProgress = Curves.easeOutCubic.transform(
          ((step2T - (i * 0.08)) / 0.60).clamp(0.0, 1.0),
        );

        x = targetOrbitX * iconProgress;
        y = floorOriginY + (targetOrbitY - floorOriginY) * iconProgress;
        scale = 0.3 + (0.7 * iconProgress);
        opacity = iconProgress.clamp(0.0, 1.0);
        rotation = (1.0 - iconProgress) * (i.isEven ? 0.6 : -0.6);
      } else if (progress < 0.729) {
        // STEP 3: CONNECT & ORBIT (Smooth planetary orbit)
        x = targetOrbitX;
        y = targetOrbitY;
        scale = 1.0;
        opacity = 1.0;
        rotation = 0.0;
      } else {
        // STEP 4: SETTLE & LAUNCH (Icons implode back into central logo)
        final implodeT = Curves.easeInOutCubic.transform(settleProgress);
        x = targetOrbitX * (1.0 - implodeT);
        y = logoYOffset + ((targetOrbitY - logoYOffset) * (1.0 - implodeT));
        scale = (1.0 - implodeT).clamp(0.0, 1.0);
        opacity = (1.0 - implodeT).clamp(0.0, 1.0);
        rotation = implodeT * 0.8;
      }

      widgets.add(
        Transform.translate(
          offset: Offset(x, y),
          child: Transform.rotate(
            angle: rotation,
            child: Transform.scale(
              scale: scale,
              child: Opacity(
                opacity: opacity,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFF140A28),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: (feat['glow'] as Color).withValues(alpha: 0.85),
                      width: 1.8,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: (feat['glow'] as Color).withValues(alpha: 0.50),
                        blurRadius: 14,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Icon(
                    feat['icon'] as IconData,
                    size: 22,
                    color: feat['color'] as Color,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return widgets;
  }
}

/// Custom Painter for Step 1 Concentric Expanding Ripples, Step 3 Dotted Orbital Ring, and Center Glowing Halo
class RippleAndOrbitCustomPainter extends CustomPainter {
  final double rippleProgress;
  final double step3Progress;
  final double settleProgress;
  final double orbitRadius;
  final double logoYOffset;
  final double orbitAngle;

  RippleAndOrbitCustomPainter({
    required this.rippleProgress,
    required this.step3Progress,
    required this.settleProgress,
    required this.orbitRadius,
    required this.logoYOffset,
    required this.orbitAngle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final center = Offset(size.width / 2, (size.height / 2) + logoYOffset);

    // -------------------------------------------------------------------------
    // 1. Step 1: Concentric Neon Ripple Circles (Expand Outward)
    // -------------------------------------------------------------------------
    if (rippleProgress > 0 && rippleProgress < 1.0) {
      for (int i = 1; i <= 3; i++) {
        final currentT = (rippleProgress - (i * 0.12)).clamp(0.0, 1.0);
        if (currentT > 0) {
          final r = 68.0 + (110.0 * Curves.easeOutCubic.transform(currentT));
          final alpha = ((1.0 - currentT) * 0.55).clamp(0.0, 1.0);

          final ripplePaint = Paint()
            ..color = const Color(0xFFA855F7).withValues(alpha: alpha)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2 - (0.6 * currentT);

          canvas.drawCircle(center, r, ripplePaint);
        }
      }
    }

    // -------------------------------------------------------------------------
    // 2. Step 3: Glowing Inner Halo Circle around Logo
    // -------------------------------------------------------------------------
    if (step3Progress > 0 && settleProgress < 1.0) {
      final haloOpacity =
          (Curves.easeIn.transform(step3Progress) *
                  (1.0 - settleProgress) *
                  0.45)
              .clamp(0.0, 1.0);

      final haloPaint = Paint()
        ..color = const Color(0xFF8B5CF6).withValues(alpha: haloOpacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

      canvas.drawCircle(center, 74.0, haloPaint);
    }

    // -------------------------------------------------------------------------
    // 3. Step 3: Dotted / Dashed Orbital Path
    // -------------------------------------------------------------------------
    if (step3Progress > 0 && settleProgress < 1.0) {
      final ringOpacity =
          (Curves.easeIn.transform(step3Progress) *
                  (1.0 - settleProgress) *
                  0.65)
              .clamp(0.0, 1.0);

      final orbitPaint = Paint()
        ..color = const Color(0xFFC084FC).withValues(alpha: ringOpacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6;

      const totalSegments = 32;
      for (int i = 0; i < totalSegments; i++) {
        if (i % 2 == 0) {
          final startAngle = orbitAngle + (i * 2 * math.pi / totalSegments);
          const sweepAngle = math.pi / totalSegments;
          canvas.drawArc(
            Rect.fromCircle(center: center, radius: orbitRadius),
            startAngle,
            sweepAngle,
            false,
            orbitPaint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant RippleAndOrbitCustomPainter oldDelegate) {
    return oldDelegate.rippleProgress != rippleProgress ||
        oldDelegate.step3Progress != step3Progress ||
        oldDelegate.settleProgress != settleProgress ||
        oldDelegate.logoYOffset != logoYOffset ||
        oldDelegate.orbitAngle != orbitAngle;
  }
}

/// Custom Painter for Step 2 Radiant Light Beam Rising from Bottom Center Platform
class RadiantFloorBeamPainter extends CustomPainter {
  final double opacity;
  final double beamProgress;

  RadiantFloorBeamPainter({required this.opacity, required this.beamProgress});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 ||
        size.height <= 0 ||
        beamProgress <= 0 ||
        opacity <= 0) {
      return;
    }

    final centerX = size.width / 2;
    final floorY = size.height * 0.74;
    final maxBeamHeight = size.height * 0.42;
    final currentHeight =
        maxBeamHeight * Curves.easeOutCubic.transform(beamProgress);

    // 1. Upward Radiant Volumetric Beam
    final beamPath = Path()
      ..moveTo(centerX - 95, floorY)
      ..lineTo(centerX - 24, floorY - currentHeight)
      ..lineTo(centerX + 24, floorY - currentHeight)
      ..lineTo(centerX + 95, floorY)
      ..close();

    final beamShader =
        LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            const Color(0xFFC084FC).withValues(alpha: 0.55 * opacity),
            const Color(0xFF8B5CF6).withValues(alpha: 0.25 * opacity),
            Colors.transparent,
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(
          Rect.fromLTWH(0, floorY - currentHeight, size.width, currentHeight),
        );

    final beamPaint = Paint()..shader = beamShader;
    canvas.drawPath(beamPath, beamPaint);

    // 2. Luminous Floor Portal Outer Glow
    final floorGlowPaint = Paint()
      ..color = const Color(0xFF9333EA).withValues(alpha: 0.75 * opacity)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);

    canvas.drawOval(
      Rect.fromCenter(center: Offset(centerX, floorY), width: 140, height: 26),
      floorGlowPaint,
    );

    // 3. Bright White-Yellow Portal Core
    final corePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85 * opacity)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    canvas.drawOval(
      Rect.fromCenter(center: Offset(centerX, floorY), width: 64, height: 12),
      corePaint,
    );
  }

  @override
  bool shouldRepaint(covariant RadiantFloorBeamPainter oldDelegate) {
    return oldDelegate.opacity != opacity ||
        oldDelegate.beamProgress != beamProgress;
  }
}

/// Floating Ambient Stardust Particles
class StoryboardParticlePainter extends CustomPainter {
  final double particleProgress;
  final double speedMultiplier;

  StoryboardParticlePainter({
    required this.particleProgress,
    required this.speedMultiplier,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final paint = Paint()..style = PaintingStyle.fill;
    final random = math.Random(1337);

    for (int i = 0; i < 36; i++) {
      final x = random.nextDouble() * size.width;
      final yInit = random.nextDouble() * size.height;
      final speed = (0.2 + (random.nextDouble() * 0.8)) * speedMultiplier;
      final radius = 1.0 + (random.nextDouble() * 2.2);

      final y =
          (yInit - (particleProgress * speed * size.height)) % size.height;
      final alpha = (0.2 + 0.6 * math.sin((particleProgress + i) * math.pi))
          .clamp(0.1, 0.8);

      paint.color =
          (i % 4 == 0
                  ? const Color(0xFFFFD600) // Golden Stardust
                  : const Color(0xFFC084FC)) // Purple Stardust
              .withValues(alpha: alpha);

      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant StoryboardParticlePainter oldDelegate) {
    return oldDelegate.particleProgress != particleProgress ||
        oldDelegate.speedMultiplier != speedMultiplier;
  }
}
