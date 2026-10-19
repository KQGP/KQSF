import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';
import '../../theme/farm_palette.dart';

/// A labelled state chip, e.g. `WET`, `RUNNING`, `RAINING`.
///
/// One component covers every such badge on the dashboard, so their shape,
/// weight and colour treatment stay identical wherever they appear. A running
/// actuator additionally breathes, which distinguishes "actively doing
/// something" from "happens to be in this state".
class StateBadge extends StatelessWidget {
  const StateBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.pulsing = false,
  });

  final String label;
  final Color color;
  final IconData? icon;

  /// Whether to breathe, used for a live "running" badge.
  final bool pulsing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return AnimatedContainer(
      duration: AppTokens.quick,
      curve: AppTokens.curve,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: FarmPalette.tint(color, 0.14),
        borderRadius: BorderRadius.circular(AppTokens.radiusPill),
        border: Border.all(color: FarmPalette.tint(color, 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (pulsing)
            PulseDot(color: color, size: 7)
          else if (icon != null)
            Icon(icon, size: 13, color: color),
          const SizedBox(width: 6),
          Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.7,
            ),
          ),
        ],
      ),
    );
  }
}

/// A dot that expands a fading halo while [active].
///
/// Stands in for motion that a static colour cannot: a running pump and a live
/// link both *breathe*, so liveness is visible from across the room without
/// reading any text.
class PulseDot extends StatefulWidget {
  const PulseDot({
    super.key,
    required this.color,
    this.size = 8,
    this.active = true,
    this.period = const Duration(milliseconds: 1600),
  });

  final Color color;
  final double size;

  /// When false the dot is still, for a state that is not live.
  final bool active;

  final Duration period;

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.period,
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.repeat();
  }

  @override
  void didUpdateWidget(PulseDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active == oldWidget.active) return;
    if (widget.active) {
      _controller.repeat();
    } else {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? child) {
          final double t = widget.active ? _controller.value : 0.0;
          return SizedBox(
            width: widget.size * 2.6,
            height: widget.size * 2.6,
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                // The halo grows from nothing to a ring and is clipped away at
                // full size, so the loop has no visible seam.
                Opacity(
                  opacity: (1 - t) * 0.45,
                  child: Container(
                    width: widget.size * (1 + t * 1.6),
                    height: widget.size * (1 + t * 1.6),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.color,
                    ),
                  ),
                ),
                Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.color,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}