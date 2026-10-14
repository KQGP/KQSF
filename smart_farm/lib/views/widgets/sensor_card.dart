import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';
import '../../theme/farm_palette.dart';
import 'gauge_ring.dart';
import 'sparkline.dart';
import 'state_badge.dart';

/// One sensor channel: the live reading, where it sits against the firmware's
/// trigger point, and how it has been trending.
///
/// Three levels of information are stacked deliberately — a bold number for
/// the current value, a ring that places it on a scale, and a sparkline that
/// puts it in time. A farm operator reads the number, the ring tells them
/// whether the board will act, and the sparkline tells them which way things
/// are going.
class SensorCard extends StatelessWidget {
  const SensorCard({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.valueText,
    required this.unitText,
    required this.fraction,
    required this.stateLabel,
    required this.stateColor,
    this.scaleLabel = '',
    this.threshold,
    this.trend = const <double>[],
    this.trendFormat,
    this.trendSuffix = '',
    this.hasReading = true,
  });

  /// Channel name, e.g. `Soil moisture`.
  final String label;

  final IconData icon;

  /// The channel's accent, used for the icon chip, the ring and the trend.
  final Color color;

  /// Formatted reading, or an em dash before the first frame arrives.
  final String valueText;

  /// Unit or scale shown under the reading, e.g. `°C` or `/ 1023`.
  final String unitText;

  /// Reading placed on the ring, 0..1.
  final double fraction;

  /// Qualitative state derived from the firmware thresholds, e.g. `Dry`.
  final String stateLabel;

  final Color stateColor;

  /// Optional caption under the reading, e.g. `fires below 600`.
  final String scaleLabel;

  /// Optional 0..1 trigger point, marked on the ring.
  final double? threshold;

  /// Recent samples for the trend, oldest first.
  final List<double> trend;

  /// Renders one sample for the min/max caption.
  final String Function(double value)? trendFormat;

  final String trendSuffix;

  /// Whether any telemetry has arrived, which is when the card stops being a
  /// placeholder. The trend's time span is stated once by the section heading
  /// above the grid, so repeating it on every card is just noise.
  final bool hasReading;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final FarmPalette palette = FarmPalette.of(context);
    final Color accent = hasReading ? color : palette.inkFaint;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _header(context, accent),
            const SizedBox(height: AppTokens.md),
            Center(
              child: GaugeRing(
                value: fraction,
                color: accent,
                threshold: threshold,
                thresholdColor: palette.warning,
                size: 142,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    AnimatedSwitcher(
                      duration: AppTokens.quick,
                      switchInCurve: AppTokens.curve,
                      // Sliding the new number in over the old one keeps a
                      // once-a-second update from flashing.
                      transitionBuilder: (Widget child, Animation<double> a) {
                        return FadeTransition(
                          opacity: a,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.35),
                              end: Offset.zero,
                            ).animate(a),
                            child: child,
                          ),
                        );
                      },
                      child: Text(
                        valueText,
                        key: ValueKey<String>(valueText),
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontSize: 34,
                          height: 1,
                          fontFeatures: AppTokens.tabularFigures,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      unitText,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: palette.inkFaint,
                        letterSpacing: 0.4,
                        fontFeatures: AppTokens.tabularFigures,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (scaleLabel.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppTokens.sm),
              Center(
                child: Text(
                  scaleLabel,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: palette.inkFaint,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
            const SizedBox(height: AppTokens.md),
            _trend(theme, palette, accent),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, Color accent) {
    final ThemeData theme = Theme.of(context);
    return Row(
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: FarmPalette.tint(accent, 0.14),
            borderRadius: BorderRadius.circular(AppTokens.radiusSm),
          ),
          child: Icon(icon, size: 17, color: accent),
        ),
        const SizedBox(width: AppTokens.sm),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: AppTokens.sm),
        StateBadge(label: stateLabel, color: stateColor),
      ],
    );
  }

  Widget _trend(ThemeData theme, FarmPalette palette, Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          height: 38,
          width: double.infinity,
          child: Sparkline(values: trend, color: accent),
        ),
        if (trendFormat != null) ...<Widget>[
          const SizedBox(height: AppTokens.sm),
          TrendRange(
            values: trend,
            format: trendFormat!,
            suffix: trendSuffix,
          ),
        ],
      ],
    );
  }
}