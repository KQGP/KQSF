import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';
import '../../theme/farm_palette.dart';

/// A ring gauge that wraps a live reading.
///
/// The arc sweeps from the lower left round to the lower right, leaving a gap
/// at the bottom for the readout. Because a probe reading only means something
/// relative to the firmware's own trigger point, the ring can also mark that
/// threshold and tint everything beyond it — so "the soil probe is at 412 and
/// the board waters below 600" is legible as a picture rather than arithmetic.
class GaugeRing extends StatelessWidget {
  const GaugeRing({
    super.key,
    required this.value,
    required this.color,
    required this.child,
    this.size = 148,
    this.thickness = 11,
    this.threshold,
    this.thresholdColor,
  });

  /// Reading as a 0..1 fraction of full scale.
  final double value;

  /// Colour of the filled arc.
  final Color color;

  /// Readout placed at the centre of the ring.
  final Widget child;

  final double size;
  final double thickness;

  /// Optional 0..1 position of the firmware's trigger point.
  final double? threshold;

  /// Colour for the portion of the arc past [threshold].
  final Color? thresholdColor;

  @override
  Widget build(BuildContext context) {
    final FarmPalette palette = FarmPalette.of(context);
    final double clamped = value.isFinite ? value.clamp(0.0, 1.0) : 0.0;

    // Animating from the previous reading to the new one makes the once-a-
    // second frame rate feel continuous rather than stuttering.
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: clamped, end: clamped),
      duration: AppTokens.measured,
      curve: AppTokens.curve,
      builder: (BuildContext context, double animated, Widget? _) {
        return SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _GaugePainter(
              value: animated,
              color: color,
              track: palette.surfaceSunken,
              threshold: threshold,
              thresholdColor: thresholdColor ?? palette.warning,
              thickness: thickness,
            ),
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(thickness + AppTokens.sm),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.value,
    required this.color,
    required this.track,
    required this.threshold,
    required this.thresholdColor,
    required this.thickness,
  });

  final double value;
  final Color color;
  final Color track;
  final double? threshold;
  final Color thresholdColor;
  final double thickness;

  /// Angle where the gauge begins: lower left.
  static const double _start = math.pi * 0.78;

  /// Total sweep: round the top and stop short of the start again.
  static const double _sweep = math.pi * 1.44;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Rect.fromLTWH(
      thickness / 2,
      thickness / 2,
      size.width - thickness,
      size.height - thickness,
    );
    if (rect.width <= 0 || rect.height <= 0) return;

    final Rect arc = rect.deflate(thickness / 2);

    final Paint trackPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(arc, _start, _sweep, false, trackPaint);

    if (value <= 0) return;

    final double reach = _sweep * value;

    // Beyond the trigger point the arc switches to the warning hue, so the
    // distance to a threshold is visible without reading the number.
    final double? mark = threshold?.clamp(0.0, 1.0);
    final bool crossesMark = mark != null && value > mark;

    if (crossesMark) {
      canvas.drawArc(
        arc,
        _start + _sweep * mark,
        reach - _sweep * mark,
        false,
        Paint()
          ..color = thresholdColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = thickness
          ..strokeCap = StrokeCap.round,
      );
    }

    canvas.drawArc(
      arc,
      _start,
      reach,
      false,
      Paint()
        ..shader = SweepGradient(
          startAngle: _start,
          endAngle: _start + _sweep,
          colors: <Color>[
            Color.lerp(color, Colors.white, 0.28)!,
            color,
          ],
        ).createShader(arc)
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness
        ..strokeCap = StrokeCap.round,
    );

    if (mark != null) {
      final double angle = _start + _sweep * mark;
      final Offset centre = rect.center;
      final Offset tick = centre +
          Offset(math.cos(angle), math.sin(angle)) * (rect.width / 2);
      final Offset inner = centre +
          Offset(math.cos(angle), math.sin(angle)) * (rect.width / 2 - thickness);
      canvas.drawLine(
        inner,
        tick,
        Paint()
          ..color = thresholdColor.withValues(alpha: 0.85)
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.value != value ||
      old.color != color ||
      old.track != track ||
      old.threshold != threshold ||
      old.thresholdColor != thresholdColor ||
      old.thickness != thickness;
}