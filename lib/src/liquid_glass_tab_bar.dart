import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:native_glass_navbar/src/liquid_glass_item.dart';

// Shader cache singleton
ui.FragmentProgram? _cachedGlassProgram;
bool _hasAttemptedShaderLoad = false;

/// Pure-Flutter reproduction of the iOS "Liquid Glass" bottom tab bar.
///
/// Works identically on both Android and iOS without PlatformView overhead,
/// rendering real convex lens refraction, magnification, chromatic aberration,
/// liquid stretching, spring dynamics, and touch tracking.
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

  /// Whether to render a centered iOS home indicator bar below.
  final bool showHomeIndicator;

  /// Force non-shader fallback mode for testing/low-end devices.
  final bool forceFallback;

  @override
  State<LiquidGlassTabBar> createState() => _LiquidGlassTabBarState();
}

class _LiquidGlassTabBarState extends State<LiquidGlassTabBar>
    with TickerProviderStateMixin {
  final GlobalKey _tabContentKey = GlobalKey();

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
  ui.Image? _capturedContentImage;
  bool _isCapturing = false;

  @override
  void initState() {
    super.initState();

    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );

    _positionController = AnimationController.unbounded(vsync: this)
      ..addListener(_onPositionTick);

    _stretchController = AnimationController.unbounded(vsync: this)
      ..addListener(_onStretchTick);

    _loadShaderIfNeeded();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _snapToTab(widget.currentIndex, animated: false);
        _captureContentImage();
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
    if (oldWidget.items.length != widget.items.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _captureContentImage());
    }
  }

  @override
  void dispose() {
    _pressController.dispose();
    _positionController.dispose();
    _stretchController.dispose();
    _capturedContentImage?.dispose();
    super.dispose();
  }

  void _onPositionTick() {
    setState(() {
      _lensCenterX = _positionController.value;
    });
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

    final spring = const SpringDescription(mass: 1.0, stiffness: 220.0, damping: 20.0);
    _positionSimulation = SpringSimulation(spring, _lensCenterX, targetX, 0.0);
    _positionController.animateWith(_positionSimulation!);

    final stretchSpring = const SpringDescription(mass: 1.0, stiffness: 300.0, damping: 18.0);
    _stretchSimulation = SpringSimulation(stretchSpring, _stretchFactor, 1.0, 0.0);
    _stretchController.animateWith(_stretchSimulation!);
  }

  double _getSlotWidth() {
    final box = context.findRenderObject() as RenderBox?;
    final totalW = box?.hasSize == true ? box!.size.width - 32.0 : 360.0;
    return totalW / widget.items.length;
  }

  Future<void> _captureContentImage() async {
    if (_isCapturing || !mounted) return;
    _isCapturing = true;

    try {
      final boundary = _tabContentKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary != null && boundary.hasSize) {
        final image = await boundary.toImage(pixelRatio: 2.0);
        if (mounted) {
          _capturedContentImage?.dispose();
          setState(() {
            _capturedContentImage = image;
          });
        }
      }
    } catch (_) {
      // Ignore transient capture
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
    _captureContentImage();
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    final slotW = _getSlotWidth();
    final minX = slotW * 0.5;
    final maxX = slotW * (widget.items.length - 0.5);

    final rawX = details.localPosition.dx;
    final clampedX = rawX.clamp(minX, maxX);
    final deltaX = details.delta.dx;

    final stretchVelocity = (deltaX.abs() / 15.0).clamp(0.0, 0.35);
    _stretchFactor = 1.0 + stretchVelocity;

    _lensCenterX = clampedX;
    _positionController.value = clampedX;
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
                                left: _lensCenterX - (lensW * scale) / 2,
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
                          RepaintBoundary(
                            key: _tabContentKey,
                            child: Row(
                              children: List.generate(widget.items.length, (index) {
                                final item = widget.items[index];
                                final isSelected = (index == widget.currentIndex);
                                return Expanded(
                                  child: _TabSlotWidget(
                                    item: item,
                                    isSelected: isSelected,
                                    accentColor: widget.accentColor,
                                    inactiveColor: widget.inactiveColor,
                                    onTap: () {
                                      _snapToTab(index, animated: true);
                                      widget.onChanged(index);
                                      HapticFeedback.selectionClick();
                                    },
                                  ),
                                );
                              }),
                            ),
                          ),
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
                              final center = Offset(_lensCenterX, widget.height / 2);

                              return Positioned.fill(
                                child: IgnorePointer(
                                  child: _LiquidGlassShaderView(
                                    program: _cachedGlassProgram,
                                    contentImage: _capturedContentImage,
                                    lensCenter: center,
                                    lensHalfSize: scaledHalfSize,
                                    cornerRadius: scaledHalfSize.height,
                                    magnification: widget.lensMagnification,
                                    refraction: widget.lensRefraction,
                                    chromaticAberration: widget.chromaticAberration,
                                    accentColor: widget.accentColor,
                                    barTint: widget.barColor,
                                    pressProgress: press,
                                    touchDotPos: _touchDotPos,
                                    fallback: widget.forceFallback || _cachedGlassProgram == null,
                                  ),
                                ),
                              );
                            },
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
                  color: Colors.white.withValues(alpha: 0.35),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TabSlotWidget extends StatelessWidget {
  const _TabSlotWidget({
    required this.item,
    required this.isSelected,
    required this.accentColor,
    required this.inactiveColor,
    required this.onTap,
  });

  final LiquidGlassTabItem item;
  final bool isSelected;
  final Color accentColor;
  final Color inactiveColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = isSelected ? accentColor : inactiveColor;
    final iconData = (isSelected && item.selectedIcon != null)
        ? item.selectedIcon!
        : item.icon;

    return Semantics(
      selected: isSelected,
      label: item.label,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(iconData, color: color, size: 24),
                if (item.badgeValue != null && item.badgeValue!.isNotEmpty)
                  Positioned(
                    right: -8,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.redAccent,
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
                color: color,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiquidGlassShaderView extends StatelessWidget {
  const _LiquidGlassShaderView({
    required this.program,
    required this.contentImage,
    required this.lensCenter,
    required this.lensHalfSize,
    required this.cornerRadius,
    required this.magnification,
    required this.refraction,
    required this.chromaticAberration,
    required this.accentColor,
    required this.barTint,
    required this.pressProgress,
    required this.touchDotPos,
    required this.fallback,
  });

  final ui.FragmentProgram? program;
  final ui.Image? contentImage;
  final Offset lensCenter;
  final Size lensHalfSize;
  final double cornerRadius;
  final double magnification;
  final double refraction;
  final double chromaticAberration;
  final Color accentColor;
  final Color barTint;
  final double pressProgress;
  final Offset touchDotPos;
  final bool fallback;

  @override
  Widget build(BuildContext context) {
    if (fallback || program == null || contentImage == null) {
      return CustomPaint(
        painter: _FallbackGlassPainter(
          lensCenter: lensCenter,
          lensHalfSize: lensHalfSize,
          cornerRadius: cornerRadius,
          accentColor: accentColor,
          pressProgress: pressProgress,
          touchDotPos: touchDotPos,
        ),
      );
    }

    return CustomPaint(
      painter: _ShaderGlassPainter(
        program: program!,
        contentImage: contentImage!,
        lensCenter: lensCenter,
        lensHalfSize: lensHalfSize,
        cornerRadius: cornerRadius,
        magnification: magnification,
        refraction: refraction,
        chromaticAberration: chromaticAberration,
        accentColor: accentColor,
        barTint: barTint,
        pressProgress: pressProgress,
        touchDotPos: touchDotPos,
      ),
    );
  }
}

class _ShaderGlassPainter extends CustomPainter {
  _ShaderGlassPainter({
    required this.program,
    required this.contentImage,
    required this.lensCenter,
    required this.lensHalfSize,
    required this.cornerRadius,
    required this.magnification,
    required this.refraction,
    required this.chromaticAberration,
    required this.accentColor,
    required this.barTint,
    required this.pressProgress,
    required this.touchDotPos,
  });

  final ui.FragmentProgram program;
  final ui.Image contentImage;
  final Offset lensCenter;
  final Size lensHalfSize;
  final double cornerRadius;
  final double magnification;
  final double refraction;
  final double chromaticAberration;
  final Color accentColor;
  final Color barTint;
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
    shader.setFloat(10, 1.5);
    shader.setFloat(11, 0.75);
    shader.setFloat(12, accentColor.r);
    shader.setFloat(13, accentColor.g);
    shader.setFloat(14, accentColor.b);
    shader.setFloat(15, accentColor.a);
    shader.setFloat(16, barTint.r);
    shader.setFloat(17, barTint.g);
    shader.setFloat(18, barTint.b);
    shader.setFloat(19, barTint.a);
    shader.setFloat(20, pressProgress);
    shader.setFloat(21, touchDotPos.dx);
    shader.setFloat(22, touchDotPos.dy);
    shader.setFloat(23, 14.0);

    shader.setImageSampler(0, contentImage);

    final paint = Paint()..shader = shader;
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant _ShaderGlassPainter old) {
    return old.lensCenter != lensCenter ||
        old.lensHalfSize != lensHalfSize ||
        old.pressProgress != pressProgress ||
        old.touchDotPos != touchDotPos ||
        old.contentImage != contentImage;
  }
}

class _FallbackGlassPainter extends CustomPainter {
  _FallbackGlassPainter({
    required this.lensCenter,
    required this.lensHalfSize,
    required this.cornerRadius,
    required this.accentColor,
    required this.pressProgress,
    required this.touchDotPos,
  });

  final Offset lensCenter;
  final Size lensHalfSize;
  final double cornerRadius;
  final Color accentColor;
  final double pressProgress;
  final Offset touchDotPos;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCenter(
      center: lensCenter,
      width: lensHalfSize.width * 2,
      height: lensHalfSize.height * 2,
    );
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(cornerRadius));

    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..shader = ui.Gradient.linear(
        Offset(rect.center.dx, rect.top),
        Offset(rect.center.dx, rect.bottom),
        [
          Colors.white.withValues(alpha: 0.8 * pressProgress),
          Colors.white.withValues(alpha: 0.2 * pressProgress),
        ],
      );
    canvas.drawRRect(rrect, strokePaint);

    final tintPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.white.withValues(alpha: 0.14 * pressProgress);
    canvas.drawRRect(rrect, tintPaint);

    if (touchDotPos != Offset.zero) {
      final dotPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = Colors.white.withValues(alpha: 0.25 * pressProgress);
      canvas.drawCircle(touchDotPos, 14.0, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _FallbackGlassPainter old) {
    return old.lensCenter != lensCenter ||
        old.lensHalfSize != lensHalfSize ||
        old.pressProgress != pressProgress ||
        old.touchDotPos != touchDotPos;
  }
}
