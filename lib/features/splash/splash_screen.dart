
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _introController;
  late final AnimationController _floatController;
  late final AnimationController _glowController;

  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;

  static const Color background = Color(0xFF080B18);
  static const Color purple = Color(0xFF8B5CF6);
  static const Color cyan = Color(0xFF38BDF8);
  static const Color white = Color(0xFFF8FAFC);

  @override
  void initState() {
    super.initState();

    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _introController,
      curve: Curves.easeOut,
    );

    _scaleAnimation = Tween<double>(
      begin: 0.88,
      end: 1,
    ).animate(
      CurvedAnimation(
        parent: _introController,
        curve: Curves.easeOutBack,
      ),
    );

    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    _introController.forward();
  }

  @override
  void dispose() {
    _introController.dispose();
    _floatController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  void _getStarted() {
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      body: Stack(
        children: [
          // Background gradient
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF10142A),
                    background,
                    Color(0xFF0D1022),
                  ],
                ),
              ),
            ),
          ),

          // Purple glow
          Positioned(
            top: 100,
            left: -100,
            child: _GlowCircle(
              color: purple.withValues(alpha: 0.18),
              size: 280,
            ),
          ),

          // Cyan glow
          Positioned(
            bottom: 130,
            right: -120,
            child: _GlowCircle(
              color: cyan.withValues(alpha: 0.12),
              size: 300,
            ),
          ),

          // Main layout
          SafeArea(
            child: Column(
              children: [
                // Top brand label
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 26,
                    vertical: 16,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: purple.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(
                            color: purple.withValues(alpha: 0.3),
                          ),
                        ),
                        child: const Icon(
                          Icons.movie_creation_rounded,
                          color: cyan,
                          size: 19,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'PITCHCUT',
                        style: TextStyle(
                          color: white,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.auto_awesome,
                              size: 12,
                              color: cyan,
                            ),
                            SizedBox(width: 5),
                            Text(
                              'AI POWERED',
                              style: TextStyle(
                                color: Color(0xFFB8C0D8),
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Animated content
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 26,
                        vertical: 12,
                      ),
                      child: FadeTransition(
                        opacity: _fadeAnimation,
                        child: ScaleTransition(
                          scale: _scaleAnimation,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Hero visual
                              _buildHeroVisual(),

                              const SizedBox(height: 38),

                              // Heading
                              const Text(
                                'CREATE BEYOND\nLIMITS.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: white,
                                  fontSize: 34,
                                  height: 1.16,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.2,
                                ),
                              ),

                              const SizedBox(height: 15),

                              // Subtitle
                              const Text(
                                'Your creative vision, powered by AI.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Color(0xFFADB5CC),
                                  fontSize: 14,
                                  height: 1.6,
                                  letterSpacing: 0.3,
                                ),
                              ),

                              const SizedBox(height: 25),

                              // Feature highlights
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 9,
                                runSpacing: 9,
                                children: const [
                                  _FeatureChip(
                                    icon: Icons.auto_awesome,
                                    label: 'AI EDITING',
                                  ),
                                  _FeatureChip(
                                    icon: Icons.movie_filter_rounded,
                                    label: 'SMART TOOLS',
                                  ),
                                  _FeatureChip(
                                    icon: Icons.high_quality_rounded,
                                    label: 'HD EXPORT',
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // Bottom section
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    26,
                    10,
                    26,
                    18,
                  ),
                  child: Column(
                    children: [
                      // Get Started button
                      SizedBox(
                        width: double.infinity,
                        height: 58,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFF9B70FF),
                                Color(0xFF7445E8),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                color: purple.withValues(alpha: 0.30),
                                blurRadius: 24,
                                offset: const Offset(0, 9),
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: _getStarted,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              foregroundColor: Colors.white,
                              shadowColor: Colors.transparent,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Get Started',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                SizedBox(width: 12),
                                Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 20,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 18),

                      // Footer
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.bolt_rounded,
                            color: cyan,
                            size: 13,
                          ),
                          SizedBox(width: 5),
                          Text(
                            'POWERED BY ARTIFICIAL INTELLIGENCE',
                            style: TextStyle(
                              color: Color(0xFF737C96),
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroVisual() {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _floatController,
        _glowController,
      ]),
      builder: (context, child) {
        final float = math.sin(
          _floatController.value * math.pi,
        ) * 7;

        final glow = 0.16 + (_glowController.value * 0.12);

        return Transform.translate(
          offset: Offset(0, -float),
          child: SizedBox(
            width: 290,
            height: 260,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Outer glow
                Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: purple.withValues(alpha: glow),
                        blurRadius: 65,
                        spreadRadius: 12,
                      ),
                    ],
                  ),
                ),

                // Main video preview card
                Transform.rotate(
                  angle: -0.055,
                  child: Container(
                    width: 205,
                    height: 225,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF252D51),
                          Color(0xFF171A35),
                          Color(0xFF101426),
                        ],
                      ),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.13),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 30,
                          offset: const Offset(0, 18),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(27),
                      child: Stack(
                        children: [
                          // Abstract cinematic background
                          Positioned(
                            top: -35,
                            right: -25,
                            child: Container(
                              width: 150,
                              height: 150,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    purple.withValues(alpha: 0.55),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                          ),

                          Positioned(
                            bottom: -40,
                            left: -30,
                            child: Container(
                              width: 160,
                              height: 160,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    cyan.withValues(alpha: 0.35),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                          ),

                          // Preview content
                          const Center(
                            child: Icon(
                              Icons.movie_filter_rounded,
                              color: Color(0xE6FFFFFF),
                              size: 76,
                            ),
                          ),

                          // Play button
                          Center(
                            child: Container(
                              width: 55,
                              height: 55,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withValues(alpha: 0.13),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.35),
                                ),
                              ),
                              child: const Icon(
                                Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 35,
                              ),
                            ),
                          ),

                          // Timeline decoration
                          Positioned(
                            bottom: 18,
                            left: 16,
                            right: 16,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: List.generate(
                                    8,
                                    (index) => Expanded(
                                      child: Container(
                                        height: 4,
                                        margin: const EdgeInsets.only(
                                          right: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: index < 5
                                              ? cyan
                                              : Colors.white.withValues(
                                                  alpha: 0.18,
                                                ),
                                          borderRadius:
                                              BorderRadius.circular(5),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'AI VIDEO STUDIO',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 8,
                                    letterSpacing: 2,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Floating AI badge
                Positioned(
                  top: 18,
                  right: 0,
                  child: _GlassBadge(
                    icon: Icons.auto_awesome,
                    label: 'AI MAGIC',
                    color: cyan,
                  ),
                ),

                // Floating 4K badge
                Positioned(
                  bottom: 24,
                  left: 0,
                  child: _GlassBadge(
                    icon: Icons.high_quality_rounded,
                    label: '4K QUALITY',
                    color: purple,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// Background glow circle
class _GlowCircle extends StatelessWidget {
  final Color color;
  final double size;

  const _GlowCircle({
    required this.color,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(
        sigmaX: 45,
        sigmaY: 45,
      ),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
        ),
      ),
    );
  }
}

// Glass badge
class _GlassBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _GlassBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: 12,
          sigmaY: 12,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 11,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF20243B).withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: color,
                size: 14,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.7,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Feature chips
class _FeatureChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _FeatureChip({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 11,
        vertical: 9,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF171B30),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: const Color(0xFF38BDF8),
            size: 13,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFB9C2D8),
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
