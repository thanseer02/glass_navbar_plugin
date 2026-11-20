// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:native_glass_navbar/native_glass_navbar.dart';

void main() {
  runApp(const LiquidGlassApp());
}

class LiquidGlassApp extends StatelessWidget {
  const LiquidGlassApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Liquid Glass Tab Bar Demo',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121214),
      ),
      home: const DemoHomeScreen(),
    );
  }
}

class DemoHomeScreen extends StatefulWidget {
  const DemoHomeScreen({super.key});

  @override
  State<DemoHomeScreen> createState() => _DemoHomeScreenState();
}

class _DemoHomeScreenState extends State<DemoHomeScreen> {
  int _currentIndex = 0;
  bool _forceFallback = false;

  final List<LiquidGlassTabItem> _tabs = const [
    LiquidGlassTabItem(
      icon: Icons.alarm,
      label: 'Alarm',
    ),
    LiquidGlassTabItem(
      icon: Icons.language,
      label: 'World Clock',
    ),
    LiquidGlassTabItem(
      icon: Icons.timer,
      label: 'Stopwatch',
    ),
    LiquidGlassTabItem(
      icon: Icons.hourglass_bottom,
      label: 'Timer',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final activeTab = _tabs[_currentIndex];

    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          // Background rich gradient & cards to showcase glass refraction
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0.4, -0.3),
                  radius: 1.2,
                  colors: [
                    Color(0xFF2E1C38),
                    Color(0xFF16161E),
                    Color(0xFF0F0F12),
                  ],
                ),
              ),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 70, 24, 140),
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        activeTab.label,
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          _forceFallback ? Icons.blur_off : Icons.blur_on,
                          color: Colors.white70,
                        ),
                        tooltip: _forceFallback ? 'Enable Shader' : 'Force Fallback',
                        onPressed: () {
                          setState(() {
                            _forceFallback = !_forceFallback;
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Mode: ${_forceFallback ? "Fallback (no shader)" : "Pure-Flutter GLSL FragmentProgram"}',
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                  const SizedBox(height: 36),

                  // Center Active Display Card
                  Center(
                    child: Container(
                      width: 220,
                      height: 220,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            const Color(0xFFFF5A5F).withValues(alpha: 0.25),
                            const Color(0xFFFF9472).withValues(alpha: 0.1),
                          ],
                        ),
                        border: Border.all(
                          color: const Color(0xFFFF5A5F).withValues(alpha: 0.35),
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            activeTab.icon,
                            size: 68,
                            color: const Color(0xFFFF5A5F),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            activeTab.label,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 48),

                  // Sample content items behind the navigation bar
                  for (int i = 1; i <= 4; i++)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Item #$i for ${activeTab.label}',
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.white70,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right,
                            color: Colors.white38,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Liquid Glass Tab Bar at the bottom
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: LiquidGlassTabBar(
              items: _tabs,
              currentIndex: _currentIndex,
              accentColor: const Color(0xFFFF5A5F),
              inactiveColor: const Color(0xFFBDBDBD),
              barColor: const Color(0xCC3A3A3A),
              indicatorColor: const Color(0xFF1C1C1C),
              height: 64,
              lensMagnification: 1.3,
              lensRefraction: 0.6,
              chromaticAberration: 0.08,
              forceFallback: _forceFallback,
              showHomeIndicator: true,
              onChanged: (newIndex) {
                setState(() {
                  _currentIndex = newIndex;
                });
              },
            ),
          ),
        ],
      ),
    );
  }
}
