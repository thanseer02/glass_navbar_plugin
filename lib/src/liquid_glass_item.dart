import 'package:flutter/widgets.dart';

/// Single item configuration for [LiquidGlassTabBar].
class LiquidGlassTabItem {
  /// Creates a [LiquidGlassTabItem].
  const LiquidGlassTabItem({
    required this.icon,
    required this.label,
    this.selectedIcon,
    this.badgeValue,
  });

  /// The icon to display when unselected.
  final IconData icon;

  /// The visible tab title.
  final String label;

  /// Optional icon to use when selected. Defaults to [icon].
  final IconData? selectedIcon;

  /// Optional badge text or counter.
  final String? badgeValue;
}
