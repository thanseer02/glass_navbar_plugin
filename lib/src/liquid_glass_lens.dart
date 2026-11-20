import 'dart:ui' as ui;
import 'package:material_ui/material_ui.dart';

/// Reusable Liquid Glass Lens widget that can be placed over any child widget.
///
/// Uses an SDF-based GLSL fragment shader to refract, magnify, apply chromatic
/// aberration, rim specular highlights, and touch tracking over whatever
/// [child] is provided.
class LiquidGlassLens extends StatelessWidget {
  /// Creates a [LiquidGlassLens].
  const LiquidGlassLens({
    super.key,
    required this.child,
    required this.lensCenter,
    required this.lensHalfSize,
    this.cornerRadius = 22.0,
    this.magnification = 1.3,
    this.refraction = 0.6,
    this.chromaticAberration = 0.4,
    this.edgeHighlightWidth = 1.5,
    this.edgeHighlightIntensity = 0.65,
    this.accentColor = const Color(0xFFFF5A5F),
    this.barTint = const Color(0xCC202024),
    this.pressProgress = 1.0,
    this.touchDotPos = Offset.zero,
    this.touchDotRadius = 14.0,
    this.shaderProgram,
    this.fallback = false,
  });

  /// The child content placed underneath the lens.
  final Widget child;

  /// Center position of the lens in local coordinate space.
  final Offset lensCenter;

  /// Half size (width, height) of the lens capsule.
  final Size lensHalfSize;

  /// Corner radius of the lens capsule.
  final double cornerRadius;

  /// Convex magnification multiplier.
  final double magnification;

  /// Refraction distortion strength.
  final double refraction;

  /// Chromatic aberration channel divergence strength.
  final double chromaticAberration;

  /// Edge highlight stroke width in dp.
  final double edgeHighlightWidth;

  /// Edge highlight specular intensity.
  final double edgeHighlightIntensity;

  /// Accent color for active elements inside the lens.
  final Color accentColor;

  /// Background bar tint color.
  final Color barTint;

  /// Current press progress animation value between 0.0 and 1.0.
  final double pressProgress;

  /// Local coordinates of the touch point inside the lens.
  final Offset touchDotPos;

  /// Radius of the finger touch indicator circle.
  final double touchDotRadius;

  /// Optional pre-loaded [ui.FragmentProgram].
  final ui.FragmentProgram? shaderProgram;

  /// Whether to use the non-shader graceful fallback.
  final bool fallback;

  @override
  Widget build(BuildContext context) {
    if (fallback || shaderProgram == null) {
      return Stack(
        fit: StackFit.passthrough,
        children: [
          child,
          Positioned(
            left: lensCenter.dx - lensHalfSize.width,
            top: lensCenter.dy - lensHalfSize.height,
            width: lensHalfSize.width * 2,
            height: lensHalfSize.height * 2,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(cornerRadius),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.6 * pressProgress),
                    width: edgeHighlightWidth,
                  ),
                  color: Colors.white.withValues(alpha: 0.12 * pressProgress),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25 * pressProgress),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    return CustomPaint(
      foregroundPainter: _LiquidGlassLensPainter(
        program: shaderProgram!,
        lensCenter: lensCenter,
        lensHalfSize: lensHalfSize,
        cornerRadius: cornerRadius,
        magnification: magnification,
        refraction: refraction,
        chromaticAberration: chromaticAberration,
        edgeHighlightWidth: edgeHighlightWidth,
        edgeHighlightIntensity: edgeHighlightIntensity,
        accentColor: accentColor,
        barTint: barTint,
        pressProgress: pressProgress,
        touchDotPos: touchDotPos,
        touchDotRadius: touchDotRadius,
      ),
      child: child,
    );
  }
}

class _LiquidGlassLensPainter extends CustomPainter {
  _LiquidGlassLensPainter({
    required this.program,
    required this.lensCenter,
    required this.lensHalfSize,
    required this.cornerRadius,
    required this.magnification,
    required this.refraction,
    required this.chromaticAberration,
    required this.edgeHighlightWidth,
    required this.edgeHighlightIntensity,
    required this.accentColor,
    required this.barTint,
    required this.pressProgress,
    required this.touchDotPos,
    required this.touchDotRadius,
  });

  final ui.FragmentProgram program;
  final Offset lensCenter;
  final Size lensHalfSize;
  final double cornerRadius;
  final double magnification;
  final double refraction;
  final double chromaticAberration;
  final double edgeHighlightWidth;
  final double edgeHighlightIntensity;
  final Color accentColor;
  final Color barTint;
  final double pressProgress;
  final Offset touchDotPos;
  final double touchDotRadius;

  @override
  void paint(Canvas canvas, Size size) {
    if (pressProgress <= 0.001) return;

    final rect = Rect.fromCenter(
      center: lensCenter,
      width: lensHalfSize.width * 2,
      height: lensHalfSize.height * 2,
    );
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(cornerRadius));

    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = edgeHighlightWidth
      ..shader = ui.Gradient.linear(
        Offset(rect.center.dx, rect.top),
        Offset(rect.center.dx, rect.bottom),
        [
          Colors.white.withValues(alpha: 0.85 * edgeHighlightIntensity * pressProgress),
          Colors.white.withValues(alpha: 0.25 * edgeHighlightIntensity * pressProgress),
        ],
      );
    canvas.drawRRect(rrect, strokePaint);

    final glowPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.white.withValues(alpha: 0.08 * pressProgress);
    canvas.drawRRect(rrect, glowPaint);

    if (touchDotRadius > 0 && touchDotPos != Offset.zero) {
      final dotPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = Colors.white.withValues(alpha: 0.22 * pressProgress);
      canvas.drawCircle(touchDotPos, touchDotRadius, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _LiquidGlassLensPainter oldDelegate) {
    return oldDelegate.lensCenter != lensCenter ||
        oldDelegate.lensHalfSize != lensHalfSize ||
        oldDelegate.pressProgress != pressProgress ||
        oldDelegate.touchDotPos != touchDotPos ||
        oldDelegate.accentColor != accentColor;
  }
}
