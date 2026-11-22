import 'dart:async';

import 'package:material_ui/material_ui.dart';

/// One slide in the home screen feature slideshow.
class FeatureSlide {
  const FeatureSlide({
    required this.title,
    required this.description,
    required this.icon,
    this.imageAsset,
    this.onTap,
  });

  final String title;
  final String description;
  final IconData icon;

  /// Optional picture, for example `assets/images/features/record.jpg`.
  ///
  /// If it is null or the file cannot be loaded, a gradient with the icon is
  /// shown instead, so the screen never breaks while pictures are missing.
  final String? imageAsset;

  /// Called when the slide is tapped. Usually opens the feature's screen.
  final VoidCallback? onTap;
}

/// A swipeable slideshow that moves on by itself every few seconds.
///
/// Auto-play pauses while a finger is on the slides, and it is switched off
/// completely when the phone's "remove animations" setting is on.
class FeatureCarousel extends StatefulWidget {
  const FeatureCarousel({
    super.key,
    required this.slides,
    this.height = 200,
    this.autoPlayInterval = const Duration(seconds: 4),
  });

  final List<FeatureSlide> slides;

  /// Slide height at normal text size. It grows a little with large text.
  final double height;

  final Duration autoPlayInterval;

  @override
  State<FeatureCarousel> createState() => _FeatureCarouselState();
}

class _FeatureCarouselState extends State<FeatureCarousel> {
  late final PageController _controller;
  Timer? _timer;
  int _index = 0;
  bool _reduceMotion = false;

  /// With two or more slides the slideshow loops forever in both directions.
  bool get _loops => widget.slides.length > 1;

  @override
  void initState() {
    super.initState();
    // Start far from zero so the user can also swipe backwards without
    // hitting an edge. Any multiple of the slide count lands on slide 1.
    _controller = PageController(
      viewportFraction: 0.88,
      initialPage: _loops ? widget.slides.length * 500 : 0,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _restartAutoPlay();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _restartAutoPlay() {
    _timer?.cancel();
    if (_reduceMotion || !_loops) return;
    _timer = Timer.periodic(widget.autoPlayInterval, (_) {
      if (!_controller.hasClients) return;
      _controller.nextPage(
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _pauseAutoPlay() => _timer?.cancel();

  @override
  Widget build(BuildContext context) {
    final slides = widget.slides;
    if (slides.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    // Give the text more room when the user has increased the font size.
    final textScale = MediaQuery.textScalerOf(context)
        .scale(1)
        .clamp(1.0, 1.4)
        .toDouble();
    final dotDuration = _reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 250);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: widget.height * textScale,
          child: Listener(
            onPointerDown: (_) => _pauseAutoPlay(),
            onPointerUp: (_) => _restartAutoPlay(),
            onPointerCancel: (_) => _restartAutoPlay(),
            child: PageView.builder(
              controller: _controller,
              padEnds: false,
              itemCount: _loops ? null : slides.length,
              onPageChanged: (page) {
                setState(() => _index = page % slides.length);
              },
              itemBuilder: (context, page) {
                final position = page % slides.length;
                return _SlideCard(
                  slide: slides[position],
                  position: position + 1,
                  total: slides.length,
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 10),
        ExcludeSemantics(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < slides.length; i++)
                AnimatedContainer(
                  duration: dotDuration,
                  curve: Curves.easeOut,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _index ? 22 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: i == _index ? scheme.primary : scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SlideCard extends StatelessWidget {
  const _SlideCard({
    required this.slide,
    required this.position,
    required this.total,
  });

  final FeatureSlide slide;
  final int position;
  final int total;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Padding(
      // Gap between neighbouring slides. No gap on the left, so the first
      // slide lines up with the rest of the screen.
      padding: const EdgeInsets.only(right: 12),
      child: Semantics(
        button: slide.onTap != null,
        onTap: slide.onTap,
        label:
            'Feature $position of $total. ${slide.title}. ${slide.description}',
        excludeSemantics: true,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _SlideBackground(slide: slide),
              // Dark fade at the bottom keeps the white text readable on any
              // picture.
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0xD9000000)],
                    stops: [0.2, 1.0],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(slide.icon, size: 20, color: Colors.white),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      slide.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      slide.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
              // Tap target with a ripple, on top of everything else.
              Positioned.fill(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(onTap: slide.onTap),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The slide's picture, or a gradient with its icon when there is no picture.
class _SlideBackground extends StatelessWidget {
  const _SlideBackground({required this.slide});

  final FeatureSlide slide;

  @override
  Widget build(BuildContext context) {
    final fallback = _GradientBackground(icon: slide.icon);
    final asset = slide.imageAsset;
    if (asset == null) return fallback;

    return Image.asset(
      asset,
      fit: BoxFit.cover,
      cacheWidth: 1080,
      errorBuilder: (context, error, stackTrace) => fallback,
    );
  }
}

class _GradientBackground extends StatelessWidget {
  const _GradientBackground({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          // Darkened a little so the white text passes contrast in any theme.
          colors: [
            Color.alphaBlend(
              Colors.black.withValues(alpha: 0.25),
              scheme.primary,
            ),
            Color.alphaBlend(
              Colors.black.withValues(alpha: 0.45),
              scheme.tertiary,
            ),
          ],
        ),
      ),
      child: Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(
            icon,
            size: 96,
            color: Colors.white.withValues(alpha: 0.18),
          ),
        ),
      ),
    );
  }
}
