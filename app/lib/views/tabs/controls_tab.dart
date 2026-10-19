import 'package:flutter/material.dart';

import '../../models/farm_telemetry.dart';
import '../../state/farm_controller.dart';
import '../../theme/app_tokens.dart';
import '../../theme/farm_palette.dart';
import '../widgets/pump_control_card.dart';
import '../widgets/roof_control_card.dart';
import '../widgets/section_header.dart';
import '../widgets/sparkline.dart';

/// Manual control over the relays and the roof.
///
/// Deliberately separate from the read-only dashboard: anything on this page
/// can change the state of the hardware, and an operator checking a reading
/// should never be one mis-tap away from starting a pump.
class ControlsTab extends StatelessWidget {
  const ControlsTab({
    super.key,
    required this.controller,
    required this.onOpenSettings,
  });

  final FarmController controller;

  /// Opens the gateway sheet, which the offline notice points at.
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final FarmTelemetry t = controller.telemetry;
    final bool online = controller.isOnline;

    return PageBody(
      children: <Widget>[
        if (!online) ...<Widget>[
          _OfflineNotice(onOpenSettings: onOpenSettings),
          const SectionGap(height: AppTokens.md),
        ],

        const SectionHeader(
          title: 'Irrigation',
          caption: 'Two relay-driven pumps. Pump 1 follows the soil probe; '
              'pump 2 is always yours to drive.',
          icon: Icons.water_drop_rounded,
        ),
        PumpControlCard(
          title: 'Pump 1',
          subtitle: 'Irrigation · waters below ${FarmTelemetry.soilDryThreshold}',
          icon: Icons.water_drop_rounded,
          accent: FarmPalette.of(context).pump,
          autoMode: t.p1Auto,
          isRunning: t.p1State,
          enabled: online,
          runningLabel: 'Watering',
          idleLabel: 'Idle',
          reason: _pump1Reason(t),
          // The soil trend sits beside the control, so the cause of the
          // decision is visible without scrolling back to the dashboard.
          trailing: MiniTrend(
            label: 'Soil',
            values: controller.history.soil.samples,
            color: FarmPalette.of(context).soil,
          ),
          onAutoModeChanged: controller.setPump1Auto,
          onRunStateChanged: controller.setPump1Power,
        ),
        const SizedBox(height: AppTokens.gutter),
        PumpControlCard(
          title: 'Pump 2',
          subtitle: 'Auxiliary · mist, dosing or feed',
          icon: Icons.opacity_rounded,
          accent: FarmPalette.of(context).pump,
          autoMode: false,
          isRunning: t.p2State,
          enabled: online,
          // The board has no automatic mode for pump 2, so there is no switch
          // to show. It is driven by hand here, or by a bare 0/1 written
          // straight to the board; either way the telemetry keeps the button in
          // step.
          manualOnly: true,
          onAutoModeChanged: (bool _) {},
          onRunStateChanged: controller.setPump2Power,
        ),
        const SectionGap(),

        const SectionHeader(
          title: 'Climate',
          caption: 'The roof pair moves together. Auto closes the tent when the '
              'rain probe goes wet.',
          icon: Icons.roofing_rounded,
        ),
        RoofControlCard(
          autoMode: t.servoAuto,
          angle: t.servoAngle,
          enabled: online,
          onAutoModeChanged: controller.setServoAuto,
          onAngleChanged: controller.setServoAngle,
        ),
        const SectionGap(),

        _ProtocolNote(),
      ],
    );
  }

  /// Explains the board's decision rather than leaving the operator to infer
  /// it from a relay being on or off.
  static String _pump1Reason(FarmTelemetry t) {
    if (!t.p1Auto) {
      return t.p1State
          ? 'Driving manually from the app. Automatic mode is off, so the '
              'board is not checking the soil probe.'
          : 'Manual control. Automatic mode is off.';
    }
    if (t.isSoilDry) {
      return 'Soil reads ${t.soil}, below the ${FarmTelemetry.soilDryThreshold} '
          'trigger — the board has the relay.';
    }
    return 'Soil reads ${t.soil}, above the ${FarmTelemetry.soilDryThreshold} '
        'trigger — the board is holding the relay open.';
  }
}

/// Shown in place of the controls when the link is down.
class _OfflineNotice extends StatelessWidget {
  const _OfflineNotice({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final FarmPalette palette = FarmPalette.of(context);

    return Card(
      color: FarmPalette.tint(palette.danger, 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        side: BorderSide(color: FarmPalette.tint(palette.danger, 0.30)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.md),
        child: Row(
          children: <Widget>[
            Icon(Icons.link_off_rounded, size: 18, color: palette.danger),
            const SizedBox(width: AppTokens.sm),
            Expanded(
              child: Text(
                'Not connected to the gateway, so commands cannot be sent. '
                'The controls below stay inert until the link is back.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: palette.danger,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(width: AppTokens.xs),
            TextButton(
              onPressed: onOpenSettings,
              style: TextButton.styleFrom(
                foregroundColor: palette.danger,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.sm,
                ),
              ),
              child: const Text('Fix'),
            ),
          ],
        ),
      ),
    );
  }
}

/// A quiet reminder of the wire contract, for anyone debugging on the bench.
class _ProtocolNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final FarmPalette palette = FarmPalette.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTokens.md),
      decoration: BoxDecoration(
        color: palette.surfaceSunken,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.terminal_rounded, size: 16, color: palette.inkFaint),
          const SizedBox(width: AppTokens.sm),
          Expanded(
            child: Text(
              'Gateway sends one JSON frame per second over '
              'ws://<host>:8765. Commands are written back on the same socket '
              'and applied by the board on its next loop.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: palette.inkFaint,
                fontSize: 11.5,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}