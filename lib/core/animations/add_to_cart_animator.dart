import 'package:flutter/material.dart';

class AddToCartAnimator {
  /// Triggers a flying animation from the [startKey] to the [endKey].
  ///
  /// - [imagePath] and [bucket] are used to render the floating image.
  /// - [onComplete] is called when the animation finishes.
  static void animate({
    required BuildContext context,
    required GlobalKey startKey,
    required GlobalKey endKey,
    required Widget imageWidget,
    required VoidCallback onComplete,
  }) {
    final startContext = startKey.currentContext;
    final endContext = endKey.currentContext;

    if (startContext == null || endContext == null) {
      // If either key is not found, just complete immediately without animation.
      onComplete();
      return;
    }

    final startBox = startContext.findRenderObject() as RenderBox;
    final endBox = endContext.findRenderObject() as RenderBox;

    final startOffset = startBox.localToGlobal(Offset.zero);
    final endOffset = endBox.localToGlobal(Offset.zero);

    final startSize = startBox.size;
    final endSize = endBox.size;

    // We'll calculate the center of the widgets for the path
    final startCenter = Offset(
      startOffset.dx + startSize.width / 2,
      startOffset.dy + startSize.height / 2,
    );
    final endCenter = Offset(
      endOffset.dx + endSize.width / 2,
      endOffset.dy + endSize.height / 2,
    );

    OverlayEntry? entry;
    final overlay = Overlay.of(context);

    // Build the animation controller using a local stateful builder wrapper
    entry = OverlayEntry(
      builder: (context) {
        return _AddToCartOverlayWidget(
          startCenter: startCenter,
          endCenter: endCenter,
          startSize: startSize,
          endSize: endSize,
          imageWidget: imageWidget,
          onAnimationComplete: () {
            entry?.remove();
            onComplete();
          },
        );
      },
    );

    overlay.insert(entry);
  }
}

class _AddToCartOverlayWidget extends StatefulWidget {
  final Offset startCenter;
  final Offset endCenter;
  final Size startSize;
  final Size endSize;
  final Widget imageWidget;
  final VoidCallback onAnimationComplete;

  const _AddToCartOverlayWidget({
    required this.startCenter,
    required this.endCenter,
    required this.startSize,
    required this.endSize,
    required this.imageWidget,
    required this.onAnimationComplete,
  });

  @override
  State<_AddToCartOverlayWidget> createState() =>
      _AddToCartOverlayWidgetState();
}

class _AddToCartOverlayWidgetState extends State<_AddToCartOverlayWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _curvedAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _curvedAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutCubic,
    );

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onAnimationComplete();
      }
    });

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _curvedAnimation.value;

        // Quadratic bezier curve point
        // Control point determines the height of the arc
        final p0 = widget.startCenter;
        final p2 = widget.endCenter;

        // Control point: pushed slightly up and to the left/right depending on direction
        final p1 = Offset(
          p0.dx + (p2.dx - p0.dx) / 2,
          p0.dy - 100, // Arc upwards
        );

        // Bezier interpolation
        final x =
            (1 - t) * (1 - t) * p0.dx + 2 * (1 - t) * t * p1.dx + t * t * p2.dx;
        final y =
            (1 - t) * (1 - t) * p0.dy + 2 * (1 - t) * t * p1.dy + t * t * p2.dy;

        // Use a fixed size for the flying dot (24x24)
        const dotSize = 24.0;

        // Optionally, fade out slightly towards the end
        final opacity = 1.0 - (t * 0.3);

        return Positioned(
          left: x - (dotSize / 2),
          top: y - (dotSize / 2),
          child: Opacity(
            opacity: opacity,
            child: SizedBox(
              width: dotSize,
              height: dotSize,
              child: widget.imageWidget,
            ),
          ),
        );
      },
    );
  }
}
