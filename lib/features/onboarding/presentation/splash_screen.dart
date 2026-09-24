import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_logo.dart';

/// Animated brand splash, shown once per cold start.
///
/// It takes over from the native launch screen (flat [AppColors.brandDeepGreen]
/// with the logo glyph — see `flutter_native_splash` in pubspec.yaml), so
/// its first frame deliberately looks identical: same green, logo at the
/// native size. Because the logo tile is the same green as the
/// background, only the glyph is visible and the hand-off is seamless.
/// From there the logo settles, "growth" rings pulse out, and the name,
/// tagline and the three audiences (farmers, buyers, drivers) fade in.
///
/// Calls [onFinished] when done; [AppEntry] decides what comes next.
class SplashScreen extends StatefulWidget {
  final VoidCallback onFinished;

  const SplashScreen({super.key, required this.onFinished});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 2400);

  /// Resting logo size; it starts scaled up to match the native splash.
  static const _logoSize = 128.0;

  /// The native splash draws the 1024px glyph image at 256dp; the glyph
  /// fills ~55% of that image but ~70% of the logo tile, so the tile has
  /// to start at ~200dp for the glyphs to line up.
  static const _nativeMatchScale = 200 / _logoSize;

  /// How far the logo rises from centre once the text fades in.
  static const _lift = 56.0;

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _duration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) widget.onFinished();
      });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Our first frame is on screen and matches the native splash —
      // safe to drop it now.
      FlutterNativeSplash.remove();
      if (!mounted) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        // Respect "remove animations": a short beat on the final frame.
        _controller.value = 1;
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) widget.onFinished();
        });
      } else {
        _controller.forward();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Progress of [_controller] mapped onto the [startMs, endMs] slice of
  /// the timeline, eased.
  double _phase(int startMs, int endMs, [Curve curve = Curves.easeOutCubic]) {
    final total = _duration.inMilliseconds;
    final t = ((_controller.value * total - startMs) / (endMs - startMs)).clamp(
      0.0,
      1.0,
    );
    return curve.transform(t);
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.brandDeepGreen,
        body: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final settle = _phase(0, 900, Curves.easeInOutCubic);
            final logoScale =
                _nativeMatchScale + (1 - _nativeMatchScale) * settle;

            return Stack(
              fit: StackFit.expand,
              children: [
                // Vignette fades in, so frame one is the flat native green.
                Opacity(
                  opacity: _phase(0, 900),
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment(0, -0.15),
                        radius: 1.1,
                        colors: [
                          Color(0xFF0B7A35),
                          AppColors.brandDeepGreen,
                          Color(0xFF033F18),
                        ],
                        stops: [0, 0.45, 1],
                      ),
                    ),
                  ),
                ),
                // Faint oversized leaves in the corners for texture.
                _CornerLeaf(
                  alignment: const Alignment(-1.35, -1.05),
                  angle: -0.5,
                  opacity: 0.07 * _phase(300, 1300),
                ),
                _CornerLeaf(
                  alignment: const Alignment(1.4, 1.1),
                  angle: 2.4,
                  opacity: 0.07 * _phase(450, 1450),
                ),
                // Logo sits at the exact screen centre on frame one (where
                // the native splash draws it), then lifts to make room
                // for the text below.
                Center(
                  child: Transform.translate(
                    offset: Offset(0, -_lift * settle),
                    child: SizedBox(
                      width: _logoSize * 2.6,
                      height: _logoSize * 2.6,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          _GrowthRing(
                            progress: _phase(700, 1900, Curves.easeOut),
                            baseSize: _logoSize,
                          ),
                          _GrowthRing(
                            progress: _phase(1000, 2200, Curves.easeOut),
                            baseSize: _logoSize,
                          ),
                          Transform.scale(
                            scale: logoScale,
                            child: const AppLogo(size: _logoSize),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Center(
                  child: Transform.translate(
                    // Just under the settled logo's bottom edge.
                    offset: const Offset(0, _logoSize / 2 - _lift + 64),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _FadeSlide(
                            progress: _phase(700, 1300),
                            child: Text(
                              'app_name'.tr(),
                              style: GoogleFonts.outfit(
                                fontSize: 38,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          _FadeSlide(
                            progress: _phase(950, 1550),
                            child: Text(
                              'splash_tagline'.tr(),
                              textAlign: TextAlign.center,
                              style: GoogleFonts.outfit(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: AppColors.brandLeaf,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _AudiencePill(
                            icon: Icons.agriculture_outlined,
                            label: 'splash_role_farmers'.tr(),
                            progress: _phase(1300, 1750),
                          ),
                          _AudiencePill(
                            icon: Icons.shopping_basket_outlined,
                            label: 'splash_role_buyers'.tr(),
                            progress: _phase(1450, 1900),
                          ),
                          _AudiencePill(
                            icon: Icons.local_shipping_outlined,
                            label: 'splash_role_drivers'.tr(),
                            progress: _phase(1600, 2050),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// A lime ring that expands out from behind the logo and fades — a
/// "something's growing" pulse.
class _GrowthRing extends StatelessWidget {
  final double progress;
  final double baseSize;

  const _GrowthRing({required this.progress, required this.baseSize});

  @override
  Widget build(BuildContext context) {
    if (progress <= 0 || progress >= 1) return const SizedBox.shrink();
    final size = baseSize * (1 + 1.5 * progress);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: AppColors.brandLeaf.withValues(alpha: 0.55 * (1 - progress)),
          width: 2,
        ),
      ),
    );
  }
}

class _FadeSlide extends StatelessWidget {
  final double progress;
  final Widget child;

  const _FadeSlide({required this.progress, required this.child});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: progress,
      child: Transform.translate(
        offset: Offset(0, 14 * (1 - progress)),
        child: child,
      ),
    );
  }
}

class _AudiencePill extends StatelessWidget {
  final IconData icon;
  final String label;
  final double progress;

  const _AudiencePill({
    required this.icon,
    required this.label,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return _FadeSlide(
      progress: progress,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppColors.brandLeaf),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CornerLeaf extends StatelessWidget {
  final Alignment alignment;
  final double angle;
  final double opacity;

  const _CornerLeaf({
    required this.alignment,
    required this.angle,
    required this.opacity,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Transform.rotate(
        angle: angle,
        child: Icon(
          Icons.eco,
          size: 260,
          color: Colors.white.withValues(alpha: opacity),
        ),
      ),
    );
  }
}
