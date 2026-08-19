import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:wearable_rotary/wearable_rotary.dart';

/// Scrollable container for Wear OS with an always-visible scrollbar and
/// rotary/touch scrolling. Every screen uses this so no content is ever cut
/// off at large system font sizes or on small/square displays, and so a
/// scroll indicator is always present (Wear "scrollbar missing" guideline).
///
/// The provided [padding] is treated as a minimum and is expanded to a
/// shape-safe inset so content never lands in the clipped corners of a round
/// display (Wear "watch shapes" guideline).
///
/// When [center] is true the content is vertically centered while it fits the
/// viewport, and becomes scrollable only once it would overflow.
class WearScrollView extends StatefulWidget {
  const WearScrollView({
    super.key,
    required this.children,
    this.padding = EdgeInsets.zero,
    this.center = false,
    this.shapeSafe = true,
  });

  final List<Widget> children;
  final EdgeInsets padding;
  final bool center;

  /// When true (default) [padding] is expanded to keep content clear of the
  /// clipped corners of round displays. Set to false for full-bleed layouts
  /// (e.g. the progress ring) that manage their own insets.
  final bool shapeSafe;

  @override
  State<WearScrollView> createState() => _WearScrollViewState();
}

class _WearScrollViewState extends State<WearScrollView> {
  /// RotaryScrollController makes the view respond to the rotating crown /
  /// bezel (Pixel Watch, Galaxy Watch) in addition to touch.
  final ScrollController _controller = RotaryScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Expands [widget.padding] to a shape-safe inset. On round displays the
  /// corners of the square canvas are clipped by the bezel; keeping content
  /// inside ~10% horizontally and ~15% vertically of the shortest side means
  /// text is never cut off at the screen edges, on any watch shape.
  EdgeInsets _safePadding(BuildContext context) {
    if (!widget.shapeSafe) return widget.padding;
    final side = MediaQuery.sizeOf(context).shortestSide;
    final h = side * 0.18; // Increased from 0.15 to be safer for text
    final v = side * 0.18;
    final p = widget.padding;
    return EdgeInsets.fromLTRB(
      math.max(p.left, h),
      math.max(p.top, v),
      math.max(p.right, h),
      math.max(p.bottom, v),
    );
  }

  /// Overlays the Wear-style curved position indicator on [scrollable].
  Widget _withIndicator(Widget scrollable) {
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (_) {
        setState(() {});
        return false;
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (_) {
          setState(() {});
          return false;
        },
        child: Stack(
          children: [
            scrollable,
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: CurvedScrollIndicatorPainter.of(_controller),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final padding = _safePadding(context);
    if (widget.center) {
      return _withIndicator(
        LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              controller: _controller,
              padding: padding,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: math.max(
                      0, constraints.maxHeight - padding.vertical),
                  // Force full width: a Column shrink-wraps to its widest
                  // child and SingleChildScrollView top-left-aligns a
                  // narrower child, which pushed all centered content to
                  // the left edge of round screens.
                  minWidth: math.max(
                      0, constraints.maxWidth - padding.horizontal),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: widget.children,
                ),
              ),
            );
          },
        ),
      );
    }
    return _withIndicator(
      ListView(
        controller: _controller,
        padding: padding,
        children: widget.children,
      ),
    );
  }
}

/// Wear OS-style curved position indicator: a short arc hugging the right
/// edge of the (round) display, like Wear Compose's PositionIndicator. The
/// thumb's length reflects how much of the content is visible and its
/// position tracks the scroll offset, so it reads as a scroll indicator
/// rather than a static stripe. Paints nothing when the content doesn't
/// scroll. Always visible while scrollable (Wear "scrollbar" guideline).
class CurvedScrollIndicatorPainter extends CustomPainter {
  CurvedScrollIndicatorPainter._(this.position, this.thumb);

  /// 0..1 scroll progress (top..bottom), or null when not scrollable yet.
  final double? position;

  /// 0..1 fraction of the content that is visible.
  final double thumb;

  factory CurvedScrollIndicatorPainter.of(ScrollController controller) {
    if (!controller.hasClients) {
      return CurvedScrollIndicatorPainter._(null, 1);
    }
    final p = controller.position;
    if (!p.hasContentDimensions || p.maxScrollExtent <= 0) {
      return CurvedScrollIndicatorPainter._(null, 1);
    }
    final pos = (p.pixels / p.maxScrollExtent).clamp(0.0, 1.0);
    final frac = p.viewportDimension /
        (p.viewportDimension + p.maxScrollExtent);
    return CurvedScrollIndicatorPainter._(pos, frac);
  }

  /// Total angular span of the indicator, centered on 3 o'clock.
  static const double _sweep = 60 * math.pi / 180;
  static const double _stroke = 3.0;
  static const double _inset = 5.0;

  @override
  void paint(Canvas canvas, Size size) {
    final pos = position;
    if (pos == null) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2 - _inset;
    final rect = Rect.fromCircle(center: center, radius: radius);
    const start = -_sweep / 2; // canvas angle 0 = 3 o'clock

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round
      ..color = Colors.white12;
    canvas.drawArc(rect, start, _sweep, false, track);

    // Keep the thumb visibly shorter than the track so its position — and
    // the fact that there is more content — is always readable.
    final thumbSweep = _sweep * thumb.clamp(0.15, 0.65);
    final thumbStart = start + (_sweep - thumbSweep) * pos;
    final paintThumb = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round
      ..color = Colors.white70;
    canvas.drawArc(rect, thumbStart, thumbSweep, false, paintThumb);
  }

  @override
  bool shouldRepaint(CurvedScrollIndicatorPainter old) =>
      old.position != position || old.thumb != thumb;
}
