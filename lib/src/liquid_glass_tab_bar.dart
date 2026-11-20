import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'liquid_glass_item.dart';

/// Pure-Flutter iOS-style Liquid Glass bottom tab bar.
///
/// Features a strict two-layer dual-raster rendering architecture:
/// - Layer A: Inactive (grey) icons & labels.
/// - Layer B: Active (accent/red) icons & labels.
///
/// Under the convex lens, Layer A is completely masked out with an anti-aliased SDF
/// boundary, and Layer B is magnified, refracted, and chromatically dispersed.
/// Zero ghosting, zero double glyphs, and zero alpha composite overlap.
class LiquidGlassTabBar extends StatefulWidget {
  /// Creates a [LiquidGlassTabBar].
  const LiquidGlassTabBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onChanged,
    this.accentColor = const Color(0xFFFF5A5F),
    this.inactiveColor = const Color(0xFFBDBDBD),
    this.barColor = const Color(0xCC202024),
    this.indicatorColor = const Color(0xFF141416),
    this.height = 64.0,
    this.lensMagnification = 1.3,
    this.lensRefraction = 0.6,
    this.chromaticAberration = 0.4,
    this.animationDuration = const Duration(milliseconds: 380),
    this.springStiffness = 110.0,
    this.springDamping = 16.0,
    this.showHomeIndicator = false,
    this.forceFallback = false,
  }) : assert(items.length >= 2, 'LiquidGlassTabBar requires at least 2 items.');

  /// List of tab items.
  final List<LiquidGlassTabItem> items;

  /// Current selected tab index.
  final int currentIndex;

  /// Callback when a tab is selected or released.
  final ValueChanged<int> onChanged;

  /// Selected tab accent color.
  final Color accentColor;

  /// Unselected tab icon/label color.
  final Color inactiveColor;

  /// Background floating bar color.
  final Color barColor;

  /// Dark filled indicator pill color in idle state.
  final Color indicatorColor;

  /// Bar height.
  final double height;

  /// Lens magnification level.
  final double lensMagnification;

  /// Lens convex refraction strength.
  final double lensRefraction;

  /// Edge chromatic aberration intensity.
  final double chromaticAberration;

  /// Duration for press and transition animations.
  final Duration animationDuration;

  /// Spring simulation stiffness for tab snapping (lower = slower, smoother movement).
  final double springStiffness;

  /// Spring simulation damping for tab snapping (higher = less oscillation).
  final double springDamping;

  /// Whether to render a centered iOS home indicator bar below.
  final bool showHomeIndicator;

  /// Force non-shader fallback mode for testing/low-end devices.
  final bool forceFallback;

  @override
  State<LiquidGlassTabBar> createState() => _LiquidGlassTabBarState();
}

class _LiquidGlassTabBarState extends State<LiquidGlassTabBar>
    with TickerProviderStateMixin {
  final GlobalKey _inactiveContentKey = GlobalKey();
  final GlobalKey _activeContentKey = GlobalKey();

  late AnimationController _pressController;
  late AnimationController _positionController;
  late AnimationController _stretchController;

  Simulation? _positionSimulation;
  Simulation? _stretchSimulation;

  double _lensCenterX = 0.0;
  double _stretchFactor = 1.0;
  Offset _touchDotPos = Offset.zero;
  bool _isDragging = false;
  int _dragHoverIndex = 0;

  static ui.FragmentProgram? _cachedGlassProgram;
  bool _hasAttemptedShaderLoad = false;

  ui.Image? _capturedInactiveImage;
  ui.Image? _capturedActiveImage;
  bool _isCapturing = false;

  @override
  void initState() {
    super.initState();

    _pressController = AnimationController(
      vsync: this,
      duration: widget.animationDuration,
    );

    _positionController = AnimationController.unbounded(vsync: this)
      ..addListener(_onPositionTick);

    _stretchController = AnimationController.unbounded(vsync: this)
      ..addListener(_onStretchTick);

    _loadShaderIfNeeded();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _snapToTab(widget.currentIndex, animated: false);
        _captureContentImages();
      }
    });
  }

  Future<void> _loadShaderIfNeeded() async {
    if (_cachedGlassProgram != null || _hasAttemptedShaderLoad) return;
    _hasAttemptedShaderLoad = true;
    try {
      ui.FragmentProgram? program;
      try {
        program = await ui.FragmentProgram.fromAsset(
          'shaders/glass_lens.frag',
        );
      } catch (_) {
        program = await ui.FragmentProgram.fromAsset(
          'packages/native_glass_navbar/shaders/glass_lens.frag',
        );
      }
      if (mounted) {
        setState(() {
          _cachedGlassProgram = program;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to load glass_lens.frag shader: $e');
      }
    }
  }

  @override
  void didUpdateWidget(covariant LiquidGlassTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex && !_isDragging) {
      _snapToTab(widget.currentIndex, animated: true);
    }
    if (oldWidget.items.length != widget.items.length ||
        oldWidget.accentColor != widget.accentColor ||
        oldWidget.inactiveColor != widget.inactiveColor) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _captureContentImages());
    }
  }

  @override
  void dispose() {
    _pressController.dispose();
    _positionController.dispose();
    _stretchController.dispose();
    _capturedInactiveImage?.dispose();
    _capturedActiveImage?.dispose();
    super.dispose();
  }

  void _onPositionTick() {
    if (mounted) {
      _lensCenterX = _positionController.value;
      // Schedule rebuild on next frame if called during layout
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
  }

  void _onStretchTick() {
    setState(() {
      _stretchFactor = _stretchController.value;
    });
  }

  void _snapToTab(int index, {required bool animated}) {
    final slotW = _getSlotWidth();
    final targetX = (index + 0.5) * slotW;

    if (!animated || !mounted) {
      _positionController.stop();
      _lensCenterX = targetX;
      _positionController.value = targetX;
      return;
    }

    final distance = (targetX - _lensCenterX).abs();
    final direction = targetX > _lensCenterX ? 1.0 : -1.0;

    if (distance > 10.0) {
      _stretchFactor = 1.0 + (distance / (slotW * widget.items.length) * 0.45).clamp(0.0, 0.4);
      _touchDotPos = Offset(targetX, widget.height / 2);
    }

    final spring = SpringDescription(
      mass: 1.0,
      stiffness: widget.springStiffness,
      damping: widget.springDamping,
    );
    _positionSimulation = SpringSimulation(
      spring,
      _lensCenterX,
      targetX,
      direction * (distance > 10.0 ? 30.0 : 0.0),
    );
    _positionController.animateWith(_positionSimulation!);

    final stretchSpring = SpringDescription(
      mass: 1.0,
      stiffness: widget.springStiffness * 1.3,
      damping: widget.springDamping,
    );
    _stretchSimulation = SpringSimulation(stretchSpring, _stretchFactor, 1.0, 0.0);
    _stretchController.animateWith(_stretchSimulation!);
  }

  double _getSlotWidth() {
    final box = context.findRenderObject() as RenderBox?;
    final totalW = box?.hasSize == true ? box!.size.width - 32.0 : 360.0;
    return totalW / widget.items.length;
  }

  Future<void> _captureContentImages() async {
    if (_isCapturing || !mounted) return;
    _isCapturing = true;

    try {
      final inactiveBoundary = _inactiveContentKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      final activeBoundary = _activeContentKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;

      if (inactiveBoundary != null && inactiveBoundary.hasSize &&
          activeBoundary != null && activeBoundary.hasSize) {
        final imgInactive = await inactiveBoundary.toImage(pixelRatio: 2.0);
        final imgActive = await activeBoundary.toImage(pixelRatio: 2.0);

        if (mounted) {
          _capturedInactiveImage?.dispose();
          _capturedActiveImage?.dispose();
          setState(() {
            _capturedInactiveImage = imgInactive;
            _capturedActiveImage = imgActive;
          });
        }
      }
    } catch (_) {
      // Ignore transient capture error during layout
    } finally {
      _isCapturing = false;
    }
  }

  void _handlePanDown(DragDownDetails details) {
    _isDragging = true;
    _pressController.forward();
    _positionController.stop();
    _stretchController.stop();

    final localPos = details.localPosition;
    _touchDotPos = localPos;
    _lensCenterX = localPos.dx.clamp(
      _getSlotWidth() * 0.5,
      _getSlotWidth() * (widget.items.length - 0.5),
    );
    _positionController.value = _lensCenterX;

    HapticFeedback.selectionClick();
    _captureContentImages();
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    final slotW = _getSlotWidth();
    final minX = slotW * 0.5;
    final maxX = slotW * (widget.items.length - 0.5);

    final rawX = details.localPosition.dx;
    final clampedX = rawX.clamp(minX, maxX);
    final deltaX = details.delta.dx;

    final stretchVelocity = (deltaX.abs() / 25.0).clamp(0.0, 0.25);
    _stretchFactor = 1.0 + stretchVelocity;

    _lensCenterX = _lensCenterX + (clampedX - _lensCenterX) * 0.45;
    _positionController.value = _lensCenterX;
    _touchDotPos = details.localPosition;

    final hoverIdx = (clampedX / slotW).floor().clamp(0, widget.items.length - 1);
    if (hoverIdx != _dragHoverIndex) {
      _dragHoverIndex = hoverIdx;
      HapticFeedback.selectionClick();
    }

    setState(() {});
  }

  void _handlePanEnd(DragEndDetails details) {
    _isDragging = false;
    _pressController.reverse();

    final slotW = _getSlotWidth();
    final closestIndex = (_lensCenterX / slotW).round().clamp(0, widget.items.length - 1);

    _snapToTab(closestIndex, animated: true);

    if (closestIndex != widget.currentIndex) {
      widget.onChanged(closestIndex);
      HapticFeedback.selectionClick();
    }
  }

  void _handlePanCancel() {
    _isDragging = false;
    _pressController.reverse();
    _snapToTab(widget.currentIndex, animated: true);
  }

  /// Builds a tab row where each slot has an independent color.
  /// [forCapture] true = all tabs same [color] (for shader texture); false = per-slot coloring.
  Widget _buildTabRow({
    required Color color,
    required bool isActiveLayer,
    int selectedIndex = -1,
    Color? selectedColor,
  }) {
    return Row(
      children: List.generate(widget.items.length, (index) {
        final item = widget.items[index];
        final isSelected = selectedIndex == index;
        final slotColor = (isSelected && selectedColor != null) ? selectedColor : color;
        final iconData = (isSelected && item.selectedIcon != null)
            ? item.selectedIcon!
            : item.icon;

        return Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(iconData, color: slotColor, size: 24),
                  if (item.badgeValue != null && item.badgeValue!.isNotEmpty)
                    Positioned(
                      right: -8,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: const Color(0xFFFF3B30),
                        ),
                        child: Text(
                          item.badgeValue!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                item.label,
                maxLines: 1,
                style: TextStyle(
                  color: slotColor,
                  fontSize: 11,
                  fontWeight: (isSelected || isActiveLayer) ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final totalHeight = widget.height + (widget.showHomeIndicator ? 20.0 : 12.0) + bottomPadding;

    return Semantics(
      container: true,
      label: 'Bottom Navigation Bar',
      child: SizedBox(
        height: totalHeight,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: SizedBox(
                height: widget.height,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final barWidth = constraints.maxWidth;
                    final slotW = barWidth / widget.items.length;
                    final lensW = (slotW * 0.92 * _stretchFactor);
                    final lensH = widget.height * 0.82;
                    final lensHalfSize = Size(lensW / 2, lensH / 2);

                    final currentPillX = _lensCenterX == 0.0
                        ? (widget.currentIndex + 0.5) * slotW
                        : _lensCenterX;

                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanDown: _handlePanDown,
                      onPanUpdate: _handlePanUpdate,
                      onPanEnd: _handlePanEnd,
                      onPanCancel: _handlePanCancel,
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: [
                          // 1. Floating Bar Background
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(widget.height / 2),
                                color: widget.barColor,
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.16),
                                  width: 1.0,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.35),
                                    blurRadius: 18,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // 2. Dark Pill Indicator (idle state behind active tab)
                          AnimatedBuilder(
                            animation: Listenable.merge([
                              _pressController,
                              _positionController,
                              _stretchController,
                            ]),
                            builder: (context, _) {
                              final press = _pressController.value;
                              final scale = 1.0 + (press * 0.18);
                              final pillOpacity = (1.0 - press).clamp(0.0, 1.0);

                              return Positioned(
                                left: currentPillX - (lensW * scale) / 2,
                                top: (widget.height - (lensH * scale)) / 2,
                                width: lensW * scale,
                                height: lensH * scale,
                                child: IgnorePointer(
                                  child: Opacity(
                                    opacity: pillOpacity,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular((lensH * scale) / 2),
                                        color: widget.indicatorColor,
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.4),
                                            blurRadius: 8,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),

                          // 3. VISIBLE tab row — always rendered, always visible.
                          //    Selected tab = accent color; all others = inactive grey.
                          //    The lens overlay will strictly replace content inside it on press.
                          RepaintBoundary(
                            key: _inactiveContentKey,
                            child: _buildTabRow(
                              color: widget.inactiveColor,
                              isActiveLayer: false,
                              selectedIndex: widget.currentIndex,
                              selectedColor: widget.accentColor,
                            ),
                          ),

                          // 4. Off-screen Active (accent) tab row for shader capture only.
                          //    Hidden behind Offstage but still laid out for rasterization.
                          Positioned(
                            left: 0, right: 0, top: 0, bottom: 0,
                            child: Offstage(
                              offstage: false,
                              child: Opacity(
                                opacity: 0.0001,
                                child: RepaintBoundary(
                                  key: _activeContentKey,
                                  child: _buildTabRow(
                                    color: widget.accentColor,
                                    isActiveLayer: true,
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // 5. Lens Shader Overlay — Only active during press/drag.
                          //    Strictly replaces content INSIDE the lens capsule only:
                          //    inside: magnified + refracted Layer B (accent); outside: transparent (shows Layer A through).
                          AnimatedBuilder(
                            animation: Listenable.merge([
                              _pressController,
                              _positionController,
                              _stretchController,
                            ]),
                            builder: (context, _) {
                              final press = _pressController.value;
                              if (press <= 0.001) return const SizedBox.shrink();

                              final scale = 1.0 + (press * 0.22);
                              final scaledHalfSize = Size(
                                lensHalfSize.width * scale,
                                lensHalfSize.height * scale,
                              );
                              final center = Offset(currentPillX, widget.height / 2);

                              return Positioned.fill(
                                child: IgnorePointer(
                                  child: _LensOnlyOverlay(
                                    program: _cachedGlassProgram,
                                    inactiveImage: _capturedInactiveImage,
                                    activeImage: _capturedActiveImage,
                                    lensCenter: center,
                                    lensHalfSize: scaledHalfSize,
                                    cornerRadius: scaledHalfSize.height,
                                    magnification: widget.lensMagnification,
                                    refraction: widget.lensRefraction,
                                    chromaticAberration: widget.chromaticAberration,
                                    pressProgress: press,
                                    touchDotPos: _touchDotPos,
                                    forceFallback: widget.forceFallback,
                                  ),
                                ),
                              );
                            },
                          ),

                          // 6. Semantic + Tap Gesture Overlay
                          Positioned.fill(
                            child: Row(
                              children: List.generate(widget.items.length, (index) {
                                final item = widget.items[index];
                                final isSelected = (index == widget.currentIndex);

                                return Expanded(
                                  child: Semantics(
                                    selected: isSelected,
                                    label: item.label,
                                    button: true,
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.translucent,
                                      onTap: () {
                                        _snapToTab(index, animated: true);
                                        widget.onChanged(index);
                                        HapticFeedback.selectionClick();
                                      },
                                    ),
                                  ),
                                );
                              }),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            if (widget.showHomeIndicator) ...[
              const SizedBox(height: 8.0),
              Container(
                width: 134.0,
                height: 4.5,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2.5),
                  color: Colors.white.withValues(alpha: 0.24),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LensOnlyOverlay extends StatelessWidget {
  const _LensOnlyOverlay({
    required this.program,
    required this.inactiveImage,
    required this.activeImage,
    required this.lensCenter,
    required this.lensHalfSize,
    required this.cornerRadius,
    required this.magnification,
    required this.refraction,
    required this.chromaticAberration,
    required this.pressProgress,
    required this.touchDotPos,
    required this.forceFallback,
  });

  final ui.FragmentProgram? program;
  final ui.Image? inactiveImage;
  final ui.Image? activeImage;
  final Offset lensCenter;
  final Size lensHalfSize;
  final double cornerRadius;
  final double magnification;
  final double refraction;
  final double chromaticAberration;
  final double pressProgress;
  final Offset touchDotPos;
  final bool forceFallback;

  @override
  Widget build(BuildContext context) {
    // Use shader when available; otherwise strict clip-based canvas fallback.
    if (!forceFallback && program != null && inactiveImage != null && activeImage != null) {
      return CustomPaint(
        painter: _DualShaderGlassPainter(
          program: program!,
          inactiveImage: inactiveImage!,
          activeImage: activeImage!,
          lensCenter: lensCenter,
          lensHalfSize: lensHalfSize,
          cornerRadius: cornerRadius,
          magnification: magnification,
          refraction: refraction,
          chromaticAberration: chromaticAberration,
          pressProgress: pressProgress,
          touchDotPos: touchDotPos,
        ),
      );
    }

    // Fallback: clip-based canvas overlay drawing only inside the lens capsule.
    return CustomPaint(
      painter: _StrictFallbackGlassPainter(
        activeImage: activeImage,
        lensCenter: lensCenter,
        lensHalfSize: lensHalfSize,
        cornerRadius: cornerRadius,
        magnification: magnification,
        pressProgress: pressProgress,
        touchDotPos: touchDotPos,
      ),
    );
  }
}

class _DualShaderGlassPainter extends CustomPainter {
  _DualShaderGlassPainter({
    required this.program,
    required this.inactiveImage,
    required this.activeImage,
    required this.lensCenter,
    required this.lensHalfSize,
    required this.cornerRadius,
    required this.magnification,
    required this.refraction,
    required this.chromaticAberration,
    required this.pressProgress,
    required this.touchDotPos,
  });

  final ui.FragmentProgram program;
  final ui.Image inactiveImage;
  final ui.Image activeImage;
  final Offset lensCenter;
  final Size lensHalfSize;
  final double cornerRadius;
  final double magnification;
  final double refraction;
  final double chromaticAberration;
  final double pressProgress;
  final Offset touchDotPos;

  @override
  void paint(Canvas canvas, Size size) {
    final shader = program.fragmentShader();

    shader.setFloat(0, size.width);
    shader.setFloat(1, size.height);
    shader.setFloat(2, lensCenter.dx);
    shader.setFloat(3, lensCenter.dy);
    shader.setFloat(4, lensHalfSize.width);
    shader.setFloat(5, lensHalfSize.height);
    shader.setFloat(6, cornerRadius);
    shader.setFloat(7, magnification);
    shader.setFloat(8, refraction);
    shader.setFloat(9, chromaticAberration);
    shader.setFloat(10, 1.5); // Highlight width
    shader.setFloat(11, 0.75); // Highlight intensity
    shader.setFloat(12, pressProgress);
    shader.setFloat(13, touchDotPos.dx);
    shader.setFloat(14, touchDotPos.dy);
    shader.setFloat(15, 14.0); // Touch dot radius

    shader.setImageSampler(0, inactiveImage);
    shader.setImageSampler(1, activeImage);

    final paint = Paint()..shader = shader;
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant _DualShaderGlassPainter old) {
    return old.lensCenter != lensCenter ||
        old.lensHalfSize != lensHalfSize ||
        old.pressProgress != pressProgress ||
        old.touchDotPos != touchDotPos ||
        old.inactiveImage != inactiveImage ||
        old.activeImage != activeImage;
  }
}

class _StrictFallbackGlassPainter extends CustomPainter {
  _StrictFallbackGlassPainter({
    required this.activeImage,
    required this.lensCenter,
    required this.lensHalfSize,
    required this.cornerRadius,
    required this.magnification,
    required this.pressProgress,
    required this.touchDotPos,
  });

  final ui.Image? activeImage;
  final Offset lensCenter;
  final Size lensHalfSize;
  final double cornerRadius;
  final double magnification;
  final double pressProgress;
  final Offset touchDotPos;

  @override
  void paint(Canvas canvas, Size size) {
    final lensRect = Rect.fromCenter(
      center: lensCenter,
      width: lensHalfSize.width * 2,
      height: lensHalfSize.height * 2,
    );
    final lensRRect = RRect.fromRectAndRadius(lensRect, Radius.circular(cornerRadius));

    // Draw Active Layer B strictly inside the lens capsule with magnification.
    // The visible inactive row (behind this overlay) handles everything outside.
    if (activeImage != null) {
      canvas.save();
      canvas.clipRRect(lensRRect);

      canvas.translate(lensCenter.dx, lensCenter.dy);
      final scale = 1.0 + (magnification - 1.0) * pressProgress;
      canvas.scale(scale, scale);
      canvas.translate(-lensCenter.dx, -lensCenter.dy);

      final src = Rect.fromLTWH(0, 0, activeImage!.width.toDouble(), activeImage!.height.toDouble());
      canvas.drawImageRect(activeImage!, src, Offset.zero & size, Paint());
      canvas.restore();
    }

    // Rim highlight & touch dot
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..shader = ui.Gradient.linear(
        Offset(lensRect.center.dx, lensRect.top),
        Offset(lensRect.center.dx, lensRect.bottom),
        [
          Colors.white.withValues(alpha: 0.85 * pressProgress),
          Colors.white.withValues(alpha: 0.25 * pressProgress),
        ],
      );
    canvas.drawRRect(lensRRect, strokePaint);

    if (touchDotPos != Offset.zero) {
      final dotPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = Colors.white.withValues(alpha: 0.25 * pressProgress);
      canvas.drawCircle(touchDotPos, 14.0, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _StrictFallbackGlassPainter old) {
    return old.lensCenter != lensCenter ||
        old.lensHalfSize != lensHalfSize ||
        old.pressProgress != pressProgress ||
        old.touchDotPos != touchDotPos ||
        old.activeImage != activeImage;
  }
}
