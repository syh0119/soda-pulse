import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:soda_pulse/core/app_store.dart';

class StarSkinBackground extends StatefulWidget {
  const StarSkinBackground({
    super.key,
    required this.accentColor,
    required this.skin,
    this.child,
  });

  final Color accentColor;
  final AppSkin skin;
  final Widget? child;

  @override
  State<StarSkinBackground> createState() => _StarSkinBackgroundState();
}

class _StarSkinBackgroundState extends State<StarSkinBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_AmbientParticle> _particles;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();

    final rng = math.Random(42);
    _particles = List<_AmbientParticle>.generate(48, (index) {
      return _AmbientParticle(
        x: rng.nextDouble(),
        y: rng.nextDouble(),
        radius: 1.0 + rng.nextDouble() * 2.6,
        speed: 0.4 + rng.nextDouble() * 0.9,
        phase: rng.nextDouble() * math.pi * 2,
        baseAlpha: 0.18 + rng.nextDouble() * 0.52,
        useAccent: index % 3 == 0,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isCover = widget.skin == AppSkin.cover;
    final bool isSoda = widget.skin == AppSkin.soda;
    final bool showParticles =
        widget.skin == AppSkin.star || widget.skin == AppSkin.soda;

    final Color complementaryColor =
        isSoda ? const Color(0xFF2FE08B) : const Color(0xFF1B7A4B);

    final HSLColor accentHsl = HSLColor.fromColor(widget.accentColor);
    final Color coverTop = accentHsl
        .withSaturation((accentHsl.saturation * 0.72).clamp(0.28, 0.78))
        .withLightness(0.22)
        .toColor();
    final Color coverMid = accentHsl
        .withSaturation((accentHsl.saturation * 0.76).clamp(0.32, 0.82))
        .withLightness(0.14)
        .toColor();
    final Color coverBottom = accentHsl
        .withSaturation((accentHsl.saturation * 0.78).clamp(0.30, 0.84))
        .withLightness(0.08)
        .toColor();

    final Color topTint = isCover
        ? coverTop
        : Color.lerp(const Color(0xFF0A0D0E), widget.accentColor, 0.14)!;
    final Color midTint = isCover
        ? coverMid
        : Color.lerp(const Color(0xFF080B0C), widget.accentColor, 0.06)!;
    final Color bottomBase =
        isCover ? coverBottom : const Color(0xFF060809);

    final Widget bg = RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final double t = _controller.value * math.pi * 2;
          final double breathA = (math.sin(t) + 1) * 0.5;
          final double breathB = (math.cos(t) + 1) * 0.5;

          return Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [topTint, midTint, bottomBase],
                    stops: const [0.0, 0.52, 1.0],
                  ),
                ),
              ),
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(
                        -0.55 + 0.10 * math.sin(t),
                        -0.65 + 0.08 * math.cos(t),
                      ),
                      radius: 0.85 + 0.12 * breathA,
                      colors: [
                        widget.accentColor.withValues(
                          alpha: (isCover ? 0.26 : 0.18) + 0.06 * breathA,
                        ),
                        widget.accentColor.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(
                        0.60 + 0.08 * math.cos(t),
                        0.50 + 0.10 * math.sin(t),
                      ),
                      radius: 0.90 + 0.12 * breathB,
                      colors: [
                        complementaryColor.withValues(
                          alpha: (isCover ? 0.18 : 0.14) + 0.06 * breathB,
                        ),
                        complementaryColor.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
              if (showParticles)
                IgnorePointer(
                  child: CustomPaint(
                    painter: _AmbientParticlePainter(
                      progress: _controller.value,
                      particles: _particles,
                      accentColor: widget.accentColor,
                      complementaryColor: complementaryColor,
                      isSoda: isSoda,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );

    if (widget.child == null) {
      return bg;
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        bg,
        widget.child!,
      ],
    );
  }
}

class _AmbientParticle {
  const _AmbientParticle({
    required this.x,
    required this.y,
    required this.radius,
    required this.speed,
    required this.phase,
    required this.baseAlpha,
    required this.useAccent,
  });

  final double x;
  final double y;
  final double radius;
  final double speed;
  final double phase;
  final double baseAlpha;
  final bool useAccent;
}

class _AmbientParticlePainter extends CustomPainter {
  const _AmbientParticlePainter({
    required this.progress,
    required this.particles,
    required this.accentColor,
    required this.complementaryColor,
    required this.isSoda,
  });

  final double progress;
  final List<_AmbientParticle> particles;
  final Color accentColor;
  final Color complementaryColor;
  final bool isSoda;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final Paint fillPaint = Paint()..style = PaintingStyle.fill;
    final Paint strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    final double cycle = progress * math.pi * 2;

    for (final p in particles) {
      final Color baseColor = p.useAccent
          ? accentColor
          : (isSoda ? complementaryColor : Colors.white);

      if (isSoda) {
        final double dy = (p.y - progress * p.speed) % 1.0;
        final double yNorm = dy < 0 ? dy + 1.0 : dy;
        final double sway =
            math.sin(cycle * 2 + p.phase) * (4.0 + p.radius * 1.5);
        final Offset center = Offset(
          (p.x * size.width + sway).clamp(0.0, size.width),
          yNorm * size.height,
        );

        final double bubbleRadius = p.radius * 1.45;
        final double alpha =
            (p.baseAlpha * (0.65 + 0.35 * math.sin(cycle + p.phase)))
                .clamp(0.05, 0.75);

        fillPaint.color = baseColor.withValues(alpha: alpha * 0.28);
        canvas.drawCircle(center, bubbleRadius, fillPaint);

        strokePaint.color = baseColor.withValues(alpha: alpha * 0.75);
        canvas.drawCircle(center, bubbleRadius, strokePaint);
      } else {
        final double twinkle =
            0.35 + 0.65 * ((math.sin(cycle * 2 * p.speed + p.phase) + 1) * 0.5);
        final double alpha = (p.baseAlpha * twinkle).clamp(0.04, 0.95);
        final Offset center = Offset(p.x * size.width, p.y * size.height);

        fillPaint.color = baseColor.withValues(alpha: alpha * 0.30);
        canvas.drawCircle(center, p.radius * 2.1, fillPaint);

        fillPaint.color = baseColor.withValues(alpha: alpha);
        canvas.drawCircle(center, p.radius * 0.85, fillPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _AmbientParticlePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.complementaryColor != complementaryColor ||
        oldDelegate.isSoda != isSoda;
  }
}
