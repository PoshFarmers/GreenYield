import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_logo.dart';

/// First-launch intro: one page per audience the marketplace connects —
/// buyers, farmers, drivers. Shown once per device, before login (see
/// [AppEntry]). Calls [onDone] from both Skip and Get started.
///
/// Layout: a deep-green panel holds the page's illustration and ends in
/// a sweeping curve with two lime "furrows" — the field lines from the
/// logo. The furrows lengthen as the user advances (the field grows),
/// and progress is shown as three field rows that fill in. Text sits
/// below, left-aligned.
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onDone;

  const OnboardingScreen({super.key, required this.onDone});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  /// Sampled from the illustrations' own backgrounds (they're flat JPEGs
  /// on green), so panel and artwork meet without a visible seam.
  static const _panelColor = Color(0xFF09642A);

  /// Width:height of the artwork's box. The source images are 1408×768
  /// (~1.83:1) with the art in the central ~62%, so at 1.3 (~71% of the
  /// width visible when scaled to height) only empty background is ever
  /// cropped off the sides.
  static const _panelAspect = 1.3;

  /// Depth of the curved bottom edge.
  static const _curveDepth = 44.0;

  static const _pages = [
    _PageData(
      image: 'assets/images/onboarding/buyer.jpeg',
      titleKey: 'onboarding_1_title',
      bodyKey: 'onboarding_1_body',
    ),
    _PageData(
      image: 'assets/images/onboarding/farmer.jpeg',
      titleKey: 'onboarding_2_title',
      bodyKey: 'onboarding_2_body',
    ),
    _PageData(
      image: 'assets/images/onboarding/driver.jpeg',
      titleKey: 'onboarding_3_title',
      bodyKey: 'onboarding_3_body',
    ),
  ];

  final _pageController = PageController();
  int _page = 0;

  bool get _isLast => _page == _pages.length - 1;

  /// Fractional page position (0.0 … 2.0) for swipe-driven effects.
  double get _pagePosition =>
      _pageController.hasClients && _pageController.position.haveDimensions
      ? _pageController.page!
      : _page.toDouble();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Decode the next pages up front so they don't pop in mid-swipe.
    for (final page in _pages) {
      precacheImage(AssetImage(page.image), context);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _next() {
    if (_isLast) {
      widget.onDone();
      return;
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Light status-bar icons over the green panel.
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final height = constraints.maxHeight;
            // Artwork size: as large as the width allows without cropping
            // into the art, capped on short / landscape screens so the
            // text and controls still fit below.
            final imageHeight = (width / _panelAspect).clamp(0.0, height * 0.5);
            // On tall phones the panel grows past the art (which centres
            // in it, flanked by the same green) instead of leaving a dead
            // gap above the buttons.
            final panelHeight = imageHeight < height * 0.44
                ? (height * 0.44).clamp(imageHeight, imageHeight * 1.35)
                : imageHeight;
            const headerHeight = 56.0;
            final greenHeight =
                topInset + headerHeight + panelHeight + _curveDepth;

            return Stack(
              children: [
                // Fixed green backdrop + furrows; only the content on it
                // swipes, so the shape stays calm and still.
                AnimatedBuilder(
                  animation: _pageController,
                  builder: (context, _) => CustomPaint(
                    size: Size(width, greenHeight),
                    painter: _FieldPanelPainter(
                      color: _panelColor,
                      furrowColor: AppColors.brandLeaf,
                      curveDepth: _curveDepth,
                      growth: _pagePosition / (_pages.length - 1),
                    ),
                  ),
                ),
                Column(
                  children: [
                    SizedBox(height: topInset),
                    SizedBox(height: headerHeight, child: _buildHeader()),
                    Expanded(
                      child: PageView.builder(
                        controller: _pageController,
                        itemCount: _pages.length,
                        onPageChanged: (i) => setState(() => _page = i),
                        itemBuilder: (context, index) => AnimatedBuilder(
                          animation: _pageController,
                          builder: (context, _) => _OnboardingPage(
                            data: _pages[index],
                            offset: (_pagePosition - index).clamp(-1.0, 1.0),
                            panelHeight: panelHeight,
                            imageHeight: imageHeight,
                            curveDepth: _curveDepth,
                          ),
                        ),
                      ),
                    ),
                    _buildFooter(),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
      child: Row(
        children: [
          // Shrinks rather than overflowing next to a long "Skip" label
          // on narrow phones.
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: AppLogo(
                size: 28,
                showName: true,
                nameStyle: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Hidden on the last page, where the main button already
          // says "Get started".
          AnimatedOpacity(
            opacity: _isLast ? 0 : 1,
            duration: const Duration(milliseconds: 200),
            child: TextButton(
              onPressed: _isLast ? null : widget.onDone,
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              child: Text('onboarding_skip'.tr()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
        child: Row(
          children: [
            AnimatedBuilder(
              animation: _pageController,
              builder: (context, _) => _FieldRowIndicator(
                count: _pages.length,
                position: _pagePosition,
              ),
            ),
            const SizedBox(width: 16),
            // Round arrow that grows into "Get started" on the last page;
            // takes whatever width is left, so a long label in si/ta
            // ellipsizes instead of overflowing on small phones.
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  child: FilledButton(
                    onPressed: _next,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(56, 56),
                      padding: EdgeInsets.symmetric(
                        horizontal: _isLast ? 28 : 0,
                      ),
                      shape: _isLast
                          ? const StadiumBorder()
                          : const CircleBorder(),
                    ),
                    child: _isLast
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  'onboarding_get_started'.tr(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.arrow_forward, size: 20),
                            ],
                          )
                        : Icon(
                            Icons.arrow_forward,
                            semanticLabel: 'onboarding_next'.tr(),
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PageData {
  final String image;
  final String titleKey;
  final String bodyKey;

  const _PageData({
    required this.image,
    required this.titleKey,
    required this.bodyKey,
  });
}

class _OnboardingPage extends StatelessWidget {
  final _PageData data;

  /// -1..1, 0 when this page is centred.
  final double offset;
  final double panelHeight;

  /// ≤ [panelHeight]; the art is centred in the panel.
  final double imageHeight;
  final double curveDepth;

  const _OnboardingPage({
    required this.data,
    required this.offset,
    required this.panelHeight,
    required this.imageHeight,
    required this.curveDepth,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visibility = (1 - offset.abs()).clamp(0.0, 1.0);
    final width = MediaQuery.sizeOf(context).width;
    final dpr = MediaQuery.devicePixelRatioOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: panelHeight,
          width: double.infinity,
          // Parallax: the art drifts at ~70% of the swipe speed, so it
          // feels set into the panel rather than glued to the page.
          child: Transform.translate(
            offset: Offset(offset * width * 0.3, 0),
            child: Opacity(
              opacity: (1 - offset.abs() * 0.7).clamp(0.0, 1.0),
              // Feather the image's own box (not the panel), so on wide
              // screens — where the art is narrower than the panel — its
              // edges still melt into the green.
              child: Center(
                child: _FeatheredEdges(
                  child: ClipRect(
                    child: Image.asset(
                      data.image,
                      // Scale by height: on narrow panels only empty
                      // background is cropped off the sides; on wide
                      // ones the art is simply flanked by more green.
                      fit: BoxFit.fitHeight,
                      height: imageHeight,
                      cacheHeight: (imageHeight * dpr).round(),
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        SizedBox(height: curveDepth + 20),
        Expanded(
          // Scrolls only if it must (landscape phones, huge text).
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Opacity(
              opacity: visibility,
              child: Transform.translate(
                offset: Offset(-offset * 32, 0),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data.titleKey.tr(),
                        style: GoogleFonts.outfit(
                          textStyle: theme.textTheme.headlineMedium,
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        data.bodyKey.tr(),
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.textTheme.bodySmall?.color,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Fades the image's rectangle out at all four edges, so the flat-green
/// artwork melts into the (near-identical) panel green — no visible
/// boundary even while it slides during a swipe.
class _FeatheredEdges extends StatelessWidget {
  final Widget child;

  const _FeatheredEdges({required this.child});

  static const _fade = [
    Colors.transparent,
    Colors.white,
    Colors.white,
    Colors.transparent,
  ];

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) => const LinearGradient(
        colors: _fade,
        stops: [0, 0.06, 0.94, 1],
      ).createShader(rect),
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: _fade,
          stops: [0, 0.05, 0.95, 1],
        ).createShader(rect),
        child: child,
      ),
    );
  }
}

/// Green panel whose bottom edge sweeps up from left to right, with two
/// lime furrows running along it — the field lines of the logo. The
/// furrows lengthen with [growth] (0 on the first page → 1 on the last).
class _FieldPanelPainter extends CustomPainter {
  final Color color;
  final Color furrowColor;
  final double curveDepth;
  final double growth;

  const _FieldPanelPainter({
    required this.color,
    required this.furrowColor,
    required this.curveDepth,
    required this.growth,
  });

  /// The bottom edge, raised by [lift] px — left end low, right end high.
  Path _edge(Size size, double lift) {
    final w = size.width;
    final h = size.height;
    return Path()
      ..moveTo(0, h - lift)
      ..cubicTo(
        w * 0.42,
        h - lift,
        w * 0.68,
        h - curveDepth * 0.35 - lift,
        w,
        h - curveDepth - lift,
      );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Panel: top edge, down the right side, back along the curve.
    final panel = Path()
      ..moveTo(0, 0)
      ..lineTo(w, 0)
      ..lineTo(w, h - curveDepth)
      ..cubicTo(w * 0.68, h - curveDepth * 0.35, w * 0.42, h, 0, h)
      ..close();
    canvas.drawPath(panel, Paint()..color = color);

    // Furrows: drawn from the right end, reaching further left as the
    // user advances through the pages.
    final reach = 0.45 + 0.4 * growth.clamp(0.0, 1.0);
    for (final (lift, alpha, stroke) in [(14.0, 1.0, 7.0), (28.0, 0.55, 5.0)]) {
      final metric = _edge(size, lift).computeMetrics().first;
      final segment = metric.extractPath(
        metric.length * (1 - reach),
        metric.length,
      );
      canvas.drawPath(
        segment,
        Paint()
          ..color = furrowColor.withValues(alpha: alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_FieldPanelPainter old) =>
      old.growth != growth ||
      old.color != color ||
      old.curveDepth != curveDepth;
}

/// Progress as three "field rows": each bar fills (left to right) as
/// the swipe passes through its page.
class _FieldRowIndicator extends StatelessWidget {
  final int count;

  /// Fractional page position, e.g. 0.5 mid-swipe from page 1 to 2.
  final double position;

  const _FieldRowIndicator({required this.count, required this.position});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (var i = 0; i < count; i++)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                width: 28,
                height: 6,
                child: Stack(
                  children: [
                    Positioned.fill(child: ColoredBox(color: scheme.outline)),
                    FractionallySizedBox(
                      widthFactor: (position - i + 1).clamp(0.0, 1.0),
                      heightFactor: 1,
                      child: ColoredBox(color: scheme.primary),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
