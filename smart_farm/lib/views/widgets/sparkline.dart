import 'package:flutter/material.dart';

import '../../theme/farm_palette.dart';
import '../../theme/app_tokens.dart';

/// A compact trend line for one sensor channel.
///
/// The board broadcasts a frame every second, so a short window of recent
/// samples is enough to show whether a reading is climbing, steady or falling —
/// the thing a single number can never tell you. The line is drawn as a
/// smoothed curve with a soft gradient wash beneath it, so a trend reads at a
/// glance without competing with the value it belongs to.
class Sparkline extends StatelessWidget {
  const Sparkline({
    super.key,
    required this.values,
    required this.color,
    this.strokeWidth = 2.2,
    this.showDot = true,
    this.fill = true,
  });

  /// Samples oldest first, as held by `ReadingSeries.samples`.
  final List<double> values;

  /// Line and wash colour, normally the channel's accent.
  final Color color;

  final double strokeWidth;

  /// Whether to mark the newest sample with a filled dot.
  final bool showDot;

  /// Whether to wash the area under the curve.
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;

    return RepaintBoundary(
      child: CustomPaint(
        painter: _SparklinePainter(
          values: values,
          color: color,
          strokeWidth: strokeWidth,
          showDot: showDot,
          fill: fill,
          // The wash sits on the card, so it needs a little more lift than a
          // line on the canvas does to stay visible in the light theme.
          washOpacity: dark ? 0.30 : 0.22,
        ),
        // A zero preferred size means the painter simply takes whatever box the
        // parent hands it. Asking for an infinite size instead would crash if
        // the chart is ever placed in an unbounded column.
        size: Size.zero,
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({
    required this.values,
    required this.color,
    required this.strokeWidth,
    required this.showDot,
    required this.fill,
    required this.washOpacity,
  });

  final List<double> values;
  final Color color;
  final double strokeWidth;
  final bool showDot;
  final bool fill;
  final double washOpacity;

  @override
  void paint(Canvas canvas, Size size) {
    // Padding keeps the line off the card's edges and stops the end dot from
    // being clipped by the bounds.
    const double inset = 4;
    final Rect bounds = Rect.fromLTWH(
      inset,
      inset,
      (size.width - inset * 2).clamp(0.0, double.infinity),
      (size.height - inset * 2).clamp(0.0, double.infinity),
    );
    if (bounds.width <= 0 || bounds.height <= 0) return;

    if (values.length < 2) {
      // Not enough history yet: a single flat baseline says "awaiting data"
      // without pretending there is a trend.
      final Paint line = Paint()
        ..color = color.withValues(alpha: 0.22)
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      final double y = bounds.center.dy;
      canvas.drawLine(
        Offset(bounds.left, y),
        Offset(bounds.right, y),
        line,
      );
      return;
    }

    double lowest = values.first;
    double highest = values.first;
    for (final double v in values) {
      if (v < lowest) lowest = v;
      if (v > highest) highest = v;
    }

    // A dead-flat channel would otherwise be stretched to the full height and
    // amplified into a dramatic curve by sub-count rounding noise.
    double span = highest - lowest;
    if (span < 1e-6) {
      lowest -= 0.5;
      span = 1.0;
    }

    final List<Offset> points = <Offset>[
      for (int i = 0; i < values.length; i++)
        Offset(
          bounds.left + bounds.width * (i / (values.length - 1)),
          bounds.bottom -
              bounds.height * ((values[i] - lowest) / span).clamp(0.0, 1.0),
        ),
    ];

    final Path line = _smoothPath(points);

    if (fill) {
      final Path wash = Path.from(line)
        ..lineTo(points.last.dx, bounds.bottom)
        ..lineTo(points.first.dx, bounds.bottom)
        ..close();
      canvas.drawPath(
        wash,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              color.withValues(alpha: washOpacity),
              color.withValues(alpha: 0.0),
            ],
          ).createShader(bounds),
      );
    }

    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    if (showDot) {
      final Offset head = points.last;
      canvas
        ..drawCircle(head, strokeWidth * 2.1, Paint()..color = color)
        ..drawCircle(
          head,
          strokeWidth * 2.1,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.9)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4,
        );
    }
  }

  /// Builds a curve that passes through every point.
  ///
  /// Control points sit halfway between neighbouring samples, which rounds the
  /// corners without the overshoot a Catmull-Rom spline can produce on the
  /// sharp step changes a soil probe makes when a pump starts.
  static Path _smoothPath(List<Offset> points) {
    final Path path = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 0; i < points.length - 1; i++) {
      final Offset current = points[i];
      final Offset next = points[i + 1];
      final Offset midpoint = Offset(
        (current.dx + next.dx) / 2,
        (current.dy + next.dy) / 2,
      );
      path.quadraticBezierTo(current.dx, current.dy, midpoint.dx, midpoint.dy);
    }
    path.lineTo(points.last.dx, points.last.dy);
    return path;
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.values.length != values.length ||
      old.values.isEmpty ||
      values.isEmpty ||
      old.values.last != values.last ||
      old.color != color;
}

/// A compact labelled trend, sized to sit beside a control rather than under a
/// heading.
///
/// Used on the pump cards to put the reading that *causes* the action next to
/// the switch that performs it, so "the relay is on" and "the soil got dry" are
/// seen in the same glance.
class MiniTrend extends StatelessWidget {
  const MiniTrend({
    super.key,
    required this.label,
    required this.values,
    required this.color,
    this.width = 132,
    this.height = 34,
  });

  /// What the trend shows, e.g. `Soil`.
  final String label;

  final List<double> values;
  final Color color;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final FarmPalette palette = FarmPalette.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: palette.inkFaint,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 3),
        SizedBox(
          width: width,
          height: height,
          child: Sparkline(values: values, color: color, strokeWidth: 1.8),
        ),
      ],
    );
  }
}

/// Small "min / max" readout shown beside a sparkline.
///
/// Gives the shape of the trend a numeric anchor, so a curve that has been
/// climbing slowly is not mistaken for a flat one.
class TrendRange extends StatelessWidget {
  const TrendRange({
    super.key,
    required this.values,
    required this.format,
    this.suffix = '',
  });

  final List<double> values;

  /// Renders one sample, e.g. `26.4 °C`.
  final String Function(double value) format;

  final String suffix;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final FarmPalette palette = FarmPalette.of(context);
    final TextStyle? style = theme.textTheme.labelSmall?.copyWith(
      color: palette.inkFaint,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
      fontFeatures: AppTokens.tabularFigures,
    );

    if (values.length < 2) {
      return Text('Collecting…', style: style);
    }

    double lowest = values.first;
    double highest = values.first;
    for (final double v in values) {
      if (v < lowest) lowest = v;
      if (v > highest) highest = v;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text('${format(lowest)}$suffix', style: style),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Icon(
            Icons.arrow_upward_rounded,
            size: 10,
            color: palette.inkFaint,
          ),
        ),
        Text('${format(highest)}$suffix', style: style),
      ],
    );
  }
}