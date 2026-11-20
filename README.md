# liquid_glass_tab_bar (native_glass_navbar)

An iOS-26-style **"Liquid Glass"** bottom tab bar and clear lens effect built with custom Flutter render objects, **GLSL fragment shaders (`ui.FragmentProgram`)**, and physics-based gesture dynamics.

Renders identically on **Android (minSdk 21+)** and **iOS** with zero platform-view overhead, real convex lens refraction, magnification, chromatic aberration, touch dot tracking, and spring liquid stretch.

---

## 🌟 Key Features

- **Pure-Flutter GLSL Fragment Shader**: Convex lens refraction, SDF capsule geometry, R/G/B chromatic aberration at edges, specular rim highlight, and inner glow.
- **Content Magnification & Tinting**: Overlapping icons and labels are magnified (`~1.2–1.4x`) and dynamically tinted with the accent color inside the lens capsule.
- **Interactive Lens & Touch Dot**: Morph from a dark idle pill into an interactive clear glass lens upon touch down, with a `~28dp` touch dot that smoothly tracks the finger.
- **Physics-Based Spring Dynamics**: Horizontal drag with squash and stretch in the motion direction, relaxing on stop and springing smoothly to the nearest tab with `HapticFeedback.selectionClick`.
- **Graceful Fallback Mode**: Automatic fallback to a high-performance vector/canvas visual effect for low-end devices or environments without fragment shader support.
- **Standalone `LiquidGlassLens`**: Reusable standalone lens widget for refracting arbitrary Flutter widgets (cards, images, buttons).
- **Backward Compatibility**: Fully preserves legacy `NativeGlassNavBar` and `NativeGlassNavBarItem` APIs.

---

## 🚀 Getting Started

### 1. Installation

In your app's `pubspec.yaml`:

```yaml
dependencies:
  native_glass_navbar: ^2.1.0
```

Ensure your shader is enabled in Flutter (included automatically when using this package):

```yaml
flutter:
  shaders:
    - packages/native_glass_navbar/shaders/glass_lens.frag
```

---

## 📖 Usage

### Tab Bar Example

```dart
import 'package:flutter/material.dart';
import 'package:native_glass_navbar/native_glass_navbar.dart';

LiquidGlassTabBar(
  currentIndex: _currentIndex,
  onChanged: (index) {
    setState(() => _currentIndex = index);
  },
  accentColor: const Color(0xFFFF5A5F),
  inactiveColor: const Color(0xFFBDBDBD),
  barColor: const Color(0xCC3A3A3A),
  indicatorColor: const Color(0xFF1C1C1C),
  height: 64,
  lensMagnification: 1.3,
  lensRefraction: 0.6,
  chromaticAberration: 0.08,
  showHomeIndicator: true,
  items: const [
    LiquidGlassTabItem(icon: Icons.alarm, label: 'Alarm'),
    LiquidGlassTabItem(icon: Icons.language, label: 'World Clock'),
    LiquidGlassTabItem(icon: Icons.timer, label: 'Stopwatch'),
    LiquidGlassTabItem(icon: Icons.hourglass_bottom, label: 'Timer'),
  ],
)
```

---

### Standalone Lens Widget

Refract any custom widget on the screen:

```dart
LiquidGlassLens(
  lensCenter: Offset(100, 30),
  lensHalfSize: Size(50, 24),
  cornerRadius: 22,
  magnification: 1.3,
  refraction: 0.6,
  chromaticAberration: 0.08,
  pressProgress: 1.0,
  accentColor: Color(0xFFFF5A5F),
  child: MyComplexCardWidget(),
)
```

---

## ⚙️ Parameters & Specifications

| Parameter | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `items` | `List<LiquidGlassTabItem>` | *Required* | List of 2 to 5 tab items (icon, label, badge). |
| `currentIndex` | `int` | *Required* | Currently active tab index. |
| `onChanged` | `ValueChanged<int>` | *Required* | Callback triggered upon tab release/tap. |
| `accentColor` | `Color` | `Color(0xFFFF5A5F)` | Color of selected icon, label, and lens tint. |
| `inactiveColor` | `Color` | `Color(0xFFBDBDBD)` | Color of unselected tab items. |
| `barColor` | `Color` | `Color(0xCC202024)` | Translucent dark-grey background of floating bar. |
| `indicatorColor` | `Color` | `Color(0xFF141416)` | Fill color of the dark idle pill behind active tab. |
| `height` | `double` | `64.0` | Bar height. |
| `lensMagnification` | `double` | `1.3` | Zoom factor inside the lens capsule. |
| `lensRefraction` | `double` | `0.6` | Lens distortion strength near capsule rims. |
| `chromaticAberration`| `double` | `0.4` | Color fringing divergence (blue/orange rims). |
| `showHomeIndicator`| `bool` | `false` | Whether to draw the centered iOS home indicator. |
| `forceFallback` | `bool` | `false` | Force non-shader fallback mode for testing. |

---

## 🛠️ Architecture & Under the Hood

1. **RepaintBoundary Texture Sampling**: Tab icons and labels are rendered inside an isolated `RepaintBoundary` and rasterized into a GPU image texture.
2. **GLSL Fragment Shader**: `glass_lens.frag` computes the Signed Distance Function (SDF) of the rounded capsule:
   $$\text{dist} = \text{sdRoundedBox}(p - \text{center}, \text{halfSize}, r)$$
3. **Refraction Field & Dispersion**: The gradient of the SDF drives an optical displacement vector that reaches peak distortion at the edges and vanishes at the center. Separate offsets are applied to R, G, and B color channels to generate physical chromatic dispersion.
4. **Physics Simulations**: Fluid horizontal transitions leverage `SpringSimulation(SpringDescription(mass: 1.0, stiffness: 220.0, damping: 20.0))` with velocity-based stretch and squashing.
