import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/farm_telemetry.dart';
import '../../theme/app_tokens.dart';
import '../../theme/farm_palette.dart';
import 'state_badge.dart';

/// Control surface for the roof servos, which hold the tent together and always
/// move as a pair.
///
/// The cover parks at 90° and opens to 180°, so manual mode spans only that
/// range. The firmware also drives the pair briefly to 0° when rain starts and
/// parks them again afterwards; that travel is not reachable by hand.
///
/// The card draws the roof it is positioning rather than only offering a
/// slider, because the useful question is "how far is the roof open?", not
/// "what number is the servo on?".
class RoofControlCard extends StatefulWidget {
  const RoofControlCard({
    super.key,
    required this.autoMode,
    required this.angle,
    required this.enabled,
    required this.onAutoModeChanged,
    required this.onAngleChanged,
  });

  /// Whether the board is driving the servo from the rain probe.
  final bool autoMode;

  /// Last known angle in degrees.
  final double angle;

  /// Whether the socket is connected and commands can be sent.
  final bool enabled;

  /// Called when the Auto switch is toggled.
  final ValueChanged<bool> onAutoModeChanged;

  /// Called with an integer angle when a manual position is chosen.
  final ValueChanged<int> onAngleChanged;

  @override
  State<RoofControlCard> createState() => _RoofControlCardState();
}

class _RoofControlCardState extends State<RoofControlCard> {
  /// Angle shown while the thumb is moving. Held separately from
  /// [RoofControlCard.angle] so the slider tracks the finger instead of
  /// snapping back to the last telemetry frame mid-drag.
  double? _dragValue;

  /// Suppresses the slider's own callbacks while a preset button is handling
  /// the update, preventing two commands for one interaction.
  bool _applyingPreset = false;

  @override
  void didUpdateWidget(RoofControlCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A frame arriving while the thumb is down must not steal the drag.
    if (_dragValue != null) return;
    if (oldWidget.autoMode && !widget.autoMode) {
      // Re-entering manual mode: seed from the angle the board last reported.
      setState(() => _dragValue = null);
    }
  }

  double get _displayAngle {
    final double value = _dragValue ?? widget.angle;
    return value.clamp(
      FarmTelemetry.servoMinAngle,
      FarmTelemetry.servoMaxAngle,
    );
  }

  /// How far open the cover is, 0 (closed) to 1 (fully open).
  double get _openness =>
      ((_displayAngle - FarmTelemetry.servoMinAngle) /
              (FarmTelemetry.servoMaxAngle - FarmTelemetry.servoMinAngle))
          .clamp(0.0, 1.0);

  void _applyAngle(double value) {
    if (_applyingPreset) return;
    setState(() => _dragValue = value);
  }

  void _commitAngle(double value) {
    if (_applyingPreset) return;
    setState(() => _dragValue = null);
    widget.onAngleChanged(
      value.round().clamp(
            FarmTelemetry.servoMinAngle.toInt(),
            FarmTelemetry.servoMaxAngle.toInt(),
          ),
    );
  }

  void _applyPreset(double angle) {
    setState(() {
      _applyingPreset = true;
      _dragValue = angle;
    });
    widget.onAngleChanged(angle.round());
    // Let the slider rebuild at the preset position before re-enabling input.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _applyingPreset = false;
        _dragValue = null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final FarmPalette palette = FarmPalette.of(context);
    final int degrees = _displayAngle.round();
    final bool manual = !widget.autoMode;
    final Color accent = widget.enabled ? palette.roof : palette.inkFaint;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: FarmPalette.tint(palette.roof, 0.14),
                    borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                  ),
                  child: Icon(
                    Icons.roofing,
                    size: 18,
                    color: palette.roof,
                  ),
                ),
                const SizedBox(width: AppTokens.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('Roof servos', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        manual
                            ? 'Manual · ${FarmTelemetry.servoMinAngle.round()}°'
                                '–${FarmTelemetry.servoMaxAngle.round()}°'
                            : 'Rain triggered',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: palette.inkSoft,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    _AngleReadout(degrees: degrees, accent: accent),
                    const SizedBox(height: AppTokens.xxs),
                    StateBadge(
                      label: _openness < 0.02
                          ? 'Closed'
                          : (_openness > 0.98 ? 'Open' : 'Part open'),
                      color: _openness > 0.02
                          ? palette.roof
                          : palette.inkFaint,
                    ),
                  ],
                ),
                // Always present, in both modes. Hiding it in manual mode
                // would strand the operator there: the only way back to auto
                // would be the board itself changing the flag.
                const SizedBox(width: AppTokens.sm),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      'AUTO',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: widget.autoMode && widget.enabled
                            ? theme.colorScheme.primary
                            : palette.inkFaint,
                        letterSpacing: 1,
                      ),
                    ),
                    Switch(
                      value: widget.autoMode,
                      onChanged: widget.enabled
                          ? widget.onAutoModeChanged
                          : null,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: AppTokens.md),
            AnimatedSize(
              duration: AppTokens.quick,
              curve: AppTokens.curve,
              alignment: Alignment.topCenter,
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final Widget dial = RoofDial(
                    openness: _openness,
                    accent: accent,
                    enabled: widget.enabled,
                  );
                  // In automatic mode the board owns the servos, so there is
                  // nothing to position by hand and the controls collapse.
                  final Widget controls = manual
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                activeTrackColor: palette.roof,
                                thumbColor: palette.roof,
                              ),
                              child: Slider(
                                value: _displayAngle,
                                min: FarmTelemetry.servoMinAngle,
                                max: FarmTelemetry.servoMaxAngle,
                                // One step per degree of usable travel, so the
                                // board is never asked for an angle it cannot
                                // reach by hand.
                                divisions:
                                    FarmTelemetry.servoMaxAngle.round() -
                                        FarmTelemetry.servoMinAngle.round(),
                                label: '$degrees°',
                                onChanged:
                                    widget.enabled ? _applyAngle : null,
                                onChangeEnd:
                                    widget.enabled ? _commitAngle : null,
                              ),
                            ),
                            Row(
                              children: <Widget>[
                                _PresetButton(
                                  key: const ValueKey<String>('servo-preset-90'),
                                  // "Closed" rather than the sketch's "Stop",
                                  // so the two presets read as a pair and match
                                  // the state badge above the diagram.
                                  label: 'Closed',
                                  degrees: 90,
                                  icon: Icons.lock_outline_rounded,
                                  accent: palette.roof,
                                  enabled: widget.enabled,
                                  isSelected: degrees == 90,
                                  onPressed: () => _applyPreset(90),
                                ),
                                const SizedBox(width: AppTokens.xs),
                                _PresetButton(
                                  key: const ValueKey<String>('servo-preset-180'),
                                  label: 'Open',
                                  degrees: 180,
                                  icon: Icons.open_in_full_rounded,
                                  accent: palette.roof,
                                  enabled: widget.enabled,
                                  isSelected: degrees == 180,
                                  onPressed: () => _applyPreset(180),
                                ),
                              ],
                            ),
                          ],
                        )
                      : const SizedBox.shrink();

                  // On a wide window the diagram and its controls sit side by
                  // side, so the card does not become a small drawing stranded
                  // in the middle of a very wide panel.
                  if (constraints.maxWidth >= 560) {
                    if (!manual) {
                      // Nothing to drive by hand, so the diagram centres itself
                      // instead of hanging off the left edge of a wide card.
                      return Center(child: dial);
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: <Widget>[
                        dial,
                        const SizedBox(width: AppTokens.lg),
                        Expanded(child: controls),
                      ],
                    );
                  }

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Center(child: dial),
                      if (manual) ...<Widget>[
                        const SizedBox(height: AppTokens.xs),
                        controls,
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Live angle readout beside the roof diagram.
class _AngleReadout extends StatelessWidget {
  const _AngleReadout({required this.degrees, required this.accent});

  final int degrees;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return AnimatedSwitcher(
      duration: AppTokens.instant,
      child: Text(
        '$degrees°',
        key: ValueKey<int>(degrees),
        style: theme.textTheme.titleLarge?.copyWith(
          color: accent,
          fontSize: 22,
          fontFeatures: AppTokens.tabularFigures,
        ),
      ),
    );
  }
}

/// A side-on diagram of the greenhouse roof, animating as it opens.
///
/// Both panels hinge on a central ridge and swing outwards, the way a vented
/// greenhouse roof actually opens. Closed, their free edges land exactly on the
/// eaves and the section is a sealed triangle; open, they lift away from the
/// eaves and the widening gap underneath is the ventilation. Drawing it this
/// way means the shape itself explains the state, rather than the number having
/// to.
class RoofDial extends StatelessWidget {
  const RoofDial({
    super.key,
    required this.openness,
    required this.accent,
    this.enabled = true,
  });

  /// 0 closed, 1 fully open.
  final double openness;

  final Color accent;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final FarmPalette palette = FarmPalette.of(context);

    return TweenAnimationBuilder<double>(
      // Seeded from the incoming value so a first build is not animated in from
      // zero, which would show a closed roof before telemetry arrives.
      tween: Tween<double>(begin: openness, end: openness),
      duration: AppTokens.measured,
      curve: AppTokens.curve,
      builder: (BuildContext context, double t, Widget? _) {
        return SizedBox(
          height: 150,
          width: 220,
          child: CustomPaint(
            painter: _RoofPainter(
              openness: t,
              accent: accent,
              eave: palette.hairline,
              wash: FarmPalette.tint(accent, 0.16),
            ),
          ),
        );
      },
    );
  }
}

class _RoofPainter extends CustomPainter {
  _RoofPainter({
    required this.openness,
    required this.accent,
    required this.eave,
    required this.wash,
  });

  final double openness;
  final Color accent;
  final Color eave;
  final Color wash;

  /// How far past the closed position the panels swing when fully open.
  static const double _openSwing = 0.46;

  @override
  void paint(Canvas canvas, Size size) {
    final double baseY = size.height * 0.86;
    final double ridgeY = baseY - size.height * 0.46;
    final double halfSpan = size.width * 0.28;

    // Panels are rigid, so their length is fixed by the closed position: the
    // distance from the ridge down to an eave.
    final double length = math.sqrt(halfSpan * halfSpan + (baseY - ridgeY) * (baseY - ridgeY));
    final double closed = math.atan2(halfSpan, baseY - ridgeY);
    final double swing = closed + openness * _openSwing;

    final Offset ridge = Offset(size.width / 2, ridgeY);
    final Offset rightTip = Offset(
      ridge.dx + length * math.sin(swing),
      ridge.dy + length * math.cos(swing),
    );
    final Offset leftTip = Offset(
      ridge.dx - length * math.sin(swing),
      ridge.dy + length * math.cos(swing),
    );
    final Offset leftEave = Offset(ridge.dx - halfSpan, baseY);
    final Offset rightEave = Offset(ridge.dx + halfSpan, baseY);

    // Greenhouse floor, extended past the eaves so the structure reads as
    // sitting on something.
    final Paint ground = Paint()
      ..color = eave
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(size.width * 0.06, baseY),
      Offset(size.width * 0.94, baseY),
      ground,
    );

    // The growing gap between panel and eave is the air path; filling it makes
    // the vent unmistakable.
    if (openness > 0.02) {
      final Path gap = Path()
        ..moveTo(rightEave.dx, rightEave.dy)
        ..lineTo(rightTip.dx, rightTip.dy)
        ..lineTo(ridge.dx, ridge.dy)
        ..lineTo(leftTip.dx, leftTip.dy)
        ..lineTo(leftEave.dx, leftEave.dy)
        ..close();
      canvas.drawPath(gap, Paint()..color = wash);
    }

    final Paint panel = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas
      ..drawLine(leftTip, ridge, panel)
      ..drawLine(ridge, rightTip, panel);

    // Ridge hinge, and the two eaves the panels rest on when closed.
    canvas.drawCircle(ridge, 4.5, Paint()..color = accent);
    canvas
      ..drawCircle(leftEave, 2.6, Paint()..color = eave)
      ..drawCircle(rightEave, 2.6, Paint()..color = eave);
  }

  @override
  bool shouldRepaint(_RoofPainter old) =>
      old.openness != openness ||
      old.accent != accent ||
      old.eave != eave ||
      old.wash != wash;
}

/// One of the fixed cover positions. Both servos move together, so each preset
/// is simply an angle for the pair.
class _PresetButton extends StatelessWidget {
  const _PresetButton({
    super.key,
    required this.label,
    required this.degrees,
    required this.icon,
    required this.accent,
    required this.enabled,
    required this.isSelected,
    required this.onPressed,
  });

  final String label;
  final int degrees;
  final IconData icon;
  final Color accent;
  final bool enabled;
  final bool isSelected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final FarmPalette palette = FarmPalette.of(context);

    return Expanded(
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppTokens.radiusMd),
            onTap: enabled ? onPressed : null,
            child: AnimatedContainer(
              duration: AppTokens.quick,
              curve: AppTokens.curve,
              padding: const EdgeInsets.symmetric(vertical: AppTokens.sm),
              decoration: BoxDecoration(
                color: isSelected
                    ? FarmPalette.tint(accent, 0.14)
                    : palette.surfaceSunken,
                borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                border: Border.all(
                  color: isSelected
                      ? FarmPalette.tint(accent, 0.5)
                      : palette.hairline,
                ),
              ),
              child: Column(
                children: <Widget>[
                  Icon(
                    icon,
                    size: 17,
                    color: isSelected ? accent : palette.inkFaint,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    label,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: isSelected ? accent : theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '$degrees°',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: palette.inkFaint,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}