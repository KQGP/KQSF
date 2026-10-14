import 'package:flutter/material.dart';

import '../../models/farm_telemetry.dart';
import '../../state/farm_controller.dart';
import '../../theme/app_tokens.dart';
import '../../theme/farm_palette.dart';
import '../widgets/connection_bar.dart';
import '../widgets/section_header.dart';
import '../widgets/sensor_card.dart';

/// Read-only view of the farm: how the link is doing, what the greenhouse
/// senses, and what the hardware is currently doing with that.
///
/// The last part is what turns a set of numbers into a picture of the farm, and
/// it doubles as the bridge to the [ControlsTab]: tapping a tile jumps
/// straight to the control that owns it.
class DashboardTab extends StatelessWidget {
  const DashboardTab({
    super.key,
    required this.controller,
    required this.onOpenControls,
  });

  final FarmController controller;

  /// Switches to the controls tab.
  final VoidCallback onOpenControls;

  @override
  Widget build(BuildContext context) {
    final FarmTelemetry t = controller.telemetry;
    final bool online = controller.isOnline;
    final FarmPalette palette = FarmPalette.of(context);

    return PageBody(
      children: <Widget>[
        ConnectionBar(
          link: controller.link,
          message: controller.statusMessage,
          gateway: controller.gatewayLabel,
          lastFrameAt: controller.lastFrameAt,
          frameError: controller.frameError,
          hostnameOnly: controller.hostnameOnly,
          onRetry: controller.ensureSession,
          onConfigure: onOpenControls,
        ),
        const SectionGap(),

        SectionHeader(
          title: 'Right now',
          caption: 'What the hardware is doing with the current readings.',
          icon: Icons.bolt_rounded,
        ),
        _ActuatorSummary(
          telemetry: t,
          online: online,
          onOpenControls: onOpenControls,
        ),
        const SectionGap(),

        SectionHeader(
          title: 'Greenhouse sensors',
          caption: 'Live probes, placed against the thresholds the board acts on.',
          icon: Icons.sensors_rounded,
          trailing: _WindowChip(
            label: controller.history.windowLabel,
          ),
        ),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final int columns = _columnsFor(constraints.maxWidth);
            return GridView.count(
              crossAxisCount: columns,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: AppTokens.gutter,
              crossAxisSpacing: AppTokens.gutter,
              // The sensor card is a fixed stack of a header, a ring gauge, a
              // trend and a caption, so a fixed extent keeps every card in the
              // grid the same height without measuring them.
              childAspectRatio: _aspectFor(columns, constraints.maxWidth),
              children: _sensorCards(t, online, controller, palette),
            );
          },
        ),
      ],
    );
  }

  static int _columnsFor(double width) {
    if (width >= 1040) return 4;
    if (width >= 600) return 2;
    return 1;
  }

  /// Keeps every card in the grid exactly as tall as the tallest one, and
  /// leaves a little slack so the fixed stack — header, ring, caption, trend —
  /// can never clip at a larger text scale.
  static const double _cardHeight = 348;

  static double _aspectFor(int columns, double width) {
    final double cardWidth = (width - AppTokens.gutter * (columns - 1)) / columns;
    return cardWidth / _cardHeight;
  }

  List<Widget> _sensorCards(
    FarmTelemetry t,
    bool online,
    FarmController controller,
    FarmPalette palette,
  ) {
    final bool has = controller.hasReading;
    final String dash = '—';

    return <Widget>[
      SensorCard(
        label: 'Soil moisture',
        icon: Icons.grass_rounded,
        color: palette.soil,
        valueText: has ? '${t.soil}' : dash,
        unitText: '/ ${FarmTelemetry.analogMax}',
        fraction: t.soilFraction,
        threshold: FarmTelemetry.soilDryThreshold / FarmTelemetry.analogMax,
        stateLabel: t.isSoilDry ? 'Dry' : 'Wet',
        stateColor: t.isSoilDry ? palette.warning : palette.soil,
        scaleLabel: 'Board waters below ${FarmTelemetry.soilDryThreshold}',
        trend: controller.history.soil.samples,
        trendFormat: (double v) => v.toStringAsFixed(0),
              hasReading: has,
      ),
      SensorCard(
        label: 'Rain',
        icon: Icons.water_drop_rounded,
        color: palette.rain,
        valueText: has ? '${t.rain}' : dash,
        unitText: '/ ${FarmTelemetry.analogMax}',
        fraction: t.rainFraction,
        threshold: FarmTelemetry.rainWetThreshold / FarmTelemetry.analogMax,
        stateLabel: t.isRaining ? 'Raining' : 'Dry',
        stateColor: t.isRaining ? palette.rain : palette.inkFaint,
        scaleLabel: 'Roof opens above ${FarmTelemetry.rainWetThreshold}',
        trend: controller.history.rain.samples,
        trendFormat: (double v) => v.toStringAsFixed(0),
              hasReading: has,
      ),
      SensorCard(
        label: 'Temperature',
        icon: Icons.thermostat_rounded,
        color: palette.temperature,
        valueText: has ? t.temp.toStringAsFixed(1) : dash,
        unitText: '°C',
        // The DHT11 reports a comfortable indoor band; anything outside it is
        // off the end of the ring rather than compressed into the middle.
        fraction: ((t.temp + 10) / 60).clamp(0.0, 1.0),
        stateLabel: online ? 'Live' : 'Stale',
        stateColor: online ? palette.temperature : palette.inkFaint,
        scaleLabel: 'DHT11 air probe',
        trend: controller.history.temp.samples,
        trendFormat: (double v) => v.toStringAsFixed(1),
        trendSuffix: '°',
              hasReading: has,
      ),
      SensorCard(
        label: 'Humidity',
        icon: Icons.water_rounded,
        color: palette.humidity,
        valueText: has ? t.hum.toStringAsFixed(0) : dash,
        unitText: '%',
        fraction: (t.hum / 100).clamp(0.0, 1.0),
        stateLabel: online ? 'Live' : 'Stale',
        stateColor: online ? palette.humidity : palette.inkFaint,
        scaleLabel: 'Relative humidity',
        trend: controller.history.hum.samples,
        trendFormat: (double v) => v.toStringAsFixed(0),
        trendSuffix: '%',
              hasReading: has,
      ),
    ];
  }
}

/// Three compact tiles summarising the actuators, each opening the controls tab.
///
/// A farm is not four numbers: it is a set of decisions. Putting the relays and
/// the roof on the read-only tab means the answer to "is anything happening
/// right now?" is above the fold, without anyone touching a control.
class _ActuatorSummary extends StatelessWidget {
  const _ActuatorSummary({
    required this.telemetry,
    required this.online,
    required this.onOpenControls,
  });

  /// Height of every summary tile: title, state, and the one-line detail.
  static const double _tileHeight = 120;

  final FarmTelemetry telemetry;
  final bool online;
  final VoidCallback onOpenControls;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final int columns = constraints.maxWidth >= 680 ? 3 : 1;
        // Derived from the real tile width so the fixed stack of title, state
        // and caption always fits, from a 390px phone to a desktop window.
        final double tileWidth =
            (constraints.maxWidth - AppTokens.gutter * (columns - 1)) / columns;
        return GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: AppTokens.gutter,
          crossAxisSpacing: AppTokens.gutter,
          childAspectRatio: tileWidth / _tileHeight,
          children: <Widget>[
            _SummaryTile(
              label: 'Pump 1 · Irrigation',
              icon: Icons.water_drop_rounded,
              accent: FarmPalette.of(context).pump,
              active: telemetry.p1State,
              activeText: 'Watering',
              idleText: 'Idle',
              detail: telemetry.p1Auto
                  ? 'Auto · waters below ${FarmTelemetry.soilDryThreshold}'
                  : 'Manual control',
              enabled: online,
              onTap: onOpenControls,
            ),
            _SummaryTile(
              label: 'Pump 2 · Auxiliary',
              icon: Icons.opacity_rounded,
              accent: FarmPalette.of(context).pump,
              active: telemetry.p2State,
              activeText: 'Running',
              idleText: 'Off',
              detail: 'Manual control',
              enabled: online,
              onTap: onOpenControls,
            ),
            _SummaryTile(
              label: 'Roof servos',
              icon: Icons.roofing_rounded,
              accent: FarmPalette.of(context).roof,
              active: telemetry.servoAngle >
                  FarmTelemetry.servoMinAngle + 0.5,
              // The angle goes in the caption rather than the headline, which
              // keeps the word short enough not to truncate in a narrow tile.
              activeText: 'Open',
              idleText: 'Closed',
              detail:
                  '${telemetry.servoAngleDegrees}° · ${telemetry.servoAuto ? 'Auto, rain triggered' : 'Manual'}',
              enabled: online,
              onTap: onOpenControls,
            ),
          ],
        );
      },
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.label,
    required this.icon,
    required this.accent,
    required this.active,
    required this.activeText,
    required this.idleText,
    required this.detail,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color accent;
  final bool active;
  final String activeText;
  final String idleText;
  final String detail;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final FarmPalette palette = FarmPalette.of(context);
    final Color tone = active ? accent : palette.inkFaint;

    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(AppTokens.radiusLg),
          child: AnimatedContainer(
            duration: AppTokens.quick,
            curve: AppTokens.curve,
            padding: const EdgeInsets.all(AppTokens.md),
            decoration: BoxDecoration(
              color: active ? FarmPalette.tint(accent, 0.10) : palette.surface,
              borderRadius: BorderRadius.circular(AppTokens.radiusLg),
              border: Border.all(
                color: active
                    ? FarmPalette.tint(accent, 0.38)
                    : palette.hairline,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(icon, size: 16, color: tone),
                    const SizedBox(width: AppTokens.xs),
                    Expanded(
                      child: Text(
                        label,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppTokens.xs),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        active ? activeText : idleText,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontSize: 20,
                          height: 1.1,
                          color: active ? accent : palette.inkSoft,
                          fontFeatures: AppTokens.tabularFigures,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: palette.inkFaint,
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: palette.inkFaint,
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Small caption chip, e.g. the span the trend covers.
class _WindowChip extends StatelessWidget {
  const _WindowChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final FarmPalette palette = FarmPalette.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: palette.surfaceSunken,
        borderRadius: BorderRadius.circular(AppTokens.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.show_chart_rounded, size: 13, color: palette.inkFaint),
          const SizedBox(width: 5),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: palette.inkSoft,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}