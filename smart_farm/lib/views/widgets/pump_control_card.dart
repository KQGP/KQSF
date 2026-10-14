import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';
import '../../theme/farm_palette.dart';
import 'state_badge.dart';

/// Control surface for a single relay-driven pump.
///
/// The board owns the relay whenever automatic mode is on, so the manual power
/// control is only offered in manual mode. That mirrors the firmware, which
/// ignores `p*_state` while `p*_auto` is true — showing a switch that does
/// nothing would be worse than showing none.
///
/// A relay has no state of its own to display, so the card spends its space on
/// the two things an operator actually needs: whether it is running, and *why*
/// the board decided that.
class PumpControlCard extends StatelessWidget {
  const PumpControlCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.autoMode,
    required this.isRunning,
    required this.enabled,
    required this.onAutoModeChanged,
    required this.onRunStateChanged,
    this.icon = Icons.water_drop,
    this.accent,
    this.manualOnly = false,
    this.runningLabel = 'Running',
    this.idleLabel = 'Idle',
    this.reason,
    this.trailing,
  });

  /// Short name, e.g. `Pump 1`.
  final String title;

  /// Purpose of the pump, e.g. `Irrigation`.
  final String subtitle;

  /// Whether the board is driving this relay itself.
  final bool autoMode;

  /// Whether the relay is currently energised.
  final bool isRunning;

  /// Whether the socket is connected and commands can be sent.
  final bool enabled;

  /// Called when the Auto switch is toggled.
  final ValueChanged<bool> onAutoModeChanged;

  /// Called when the manual power control is toggled.
  final ValueChanged<bool> onRunStateChanged;

  final IconData icon;

  /// Accent colour, defaulting to the palette's pump hue.
  final Color? accent;

  /// When true the Auto switch is hidden and only the on/off control is shown.
  ///
  /// The firmware has no automatic rule for every relay — only Pump 1 is driven
  /// from the soil threshold — so for the others a mode switch would be a
  /// control that changes nothing.
  final bool manualOnly;

  /// Wording for the energised state.
  final String runningLabel;

  /// Wording for the de-energised state in automatic mode.
  final String idleLabel;

  /// Plain-language explanation of the board's current decision, e.g.
  /// `Soil 612 is above the 600 trigger — resting`.
  final String? reason;

  /// Optional widget pinned to the trailing edge of the control row, used to
  /// show the reading that drives this pump alongside the control that acts on
  /// it.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final FarmPalette palette = FarmPalette.of(context);
    final Color tint = accent ?? palette.pump;
    // Pump 2 has no automatic rule, so "board controlled" never applies to it
    // even though the telemetry field defaults to true.
    final bool autoOwned = autoMode && !manualOnly;

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
                    color: FarmPalette.tint(tint, 0.14),
                    borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                  ),
                  child: Icon(icon, size: 18, color: tint),
                ),
                const SizedBox(width: AppTokens.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(title, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: palette.inkSoft,
                          fontSize: 12,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (!manualOnly) ...<Widget>[
                  const SizedBox(width: AppTokens.xs),
                  _AutoSwitch(
                    value: autoMode,
                    enabled: enabled,
                    onChanged: onAutoModeChanged,
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppTokens.md),
            // One row, one meaning: the control on the left says what the relay
            // is doing, the badge on the right repeats it for scanning. The
            // control is width-capped so it does not stretch into a full-width
            // slab on a desktop window.
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                // The driving sensor's trend is a bonus, not part of the
                // control, so it is dropped on a narrow card where it would
                // squeeze the control itself.
                final bool showTrend = trailing != null && constraints.maxWidth >= 520;

                return Row(
                  children: <Widget>[
                    Flexible(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 300),
                        child: SizedBox(
                          width: 300,
                          child: autoOwned
                              ? _BoardOwnedBanner(accent: tint, enabled: enabled)
                              : _PowerToggle(
                                  key: ValueKey<String>('pump-power-$title'),
                                  active: isRunning,
                                  enabled: enabled,
                                  accent: tint,
                                  labelOn: 'ON',
                                  labelOff: 'OFF',
                                  icon: Icons.power_settings_new_rounded,
                                  onPressed: () => onRunStateChanged(!isRunning),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppTokens.sm),
                    StateBadge(
                      label: isRunning
                          ? runningLabel
                          : (autoOwned ? idleLabel : 'Off'),
                      color: isRunning ? palette.online : palette.inkFaint,
                      pulsing: isRunning,
                    ),
                    if (showTrend) ...<Widget>[
                      const Spacer(),
                      const SizedBox(width: AppTokens.md),
                      trailing!,
                    ],
                  ],
                );
              },
            ),
            if (reason != null && reason!.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppTokens.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    autoOwned ? Icons.auto_awesome : Icons.tips_and_updates,
                    size: 14,
                    color: palette.inkFaint,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      reason!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: palette.inkFaint,
                        fontSize: 11.5,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Auto switch with a label, used on the pump and roof cards.
class _AutoSwitch extends StatelessWidget {
  const _AutoSwitch({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final FarmPalette palette = FarmPalette.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          'AUTO',
          style: theme.textTheme.labelSmall?.copyWith(
            color: value && enabled ? theme.colorScheme.primary : palette.inkFaint,
            letterSpacing: 1,
          ),
        ),
        Switch(
          value: value,
          onChanged: enabled ? onChanged : null,
        ),
      ],
    );
  }
}

/// The wide on/off control shown in manual mode.
class _PowerToggle extends StatelessWidget {
  const _PowerToggle({
    super.key,
    required this.active,
    required this.enabled,
    required this.accent,
    required this.labelOn,
    required this.labelOff,
    required this.icon,
    required this.onPressed,
  });

  final bool active;
  final bool enabled;
  final Color accent;
  final String labelOn;
  final String labelOff;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final FarmPalette palette = FarmPalette.of(context);

    // Off reads as an inert well; on reads as the accent, so the control's
    // state is the strongest signal on the card.
    final Color background = active
        ? FarmPalette.tint(accent, 0.16)
        : palette.surfaceSunken;
    final Color border = active
        ? FarmPalette.tint(accent, 0.55)
        : palette.hairline;
    final Color foreground = active ? accent : palette.inkFaint;

    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          child: AnimatedContainer(
            duration: AppTokens.quick,
            curve: AppTokens.curve,
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: AppTokens.md),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(AppTokens.radiusMd),
              border: Border.all(color: border, width: active ? 1.6 : 1),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(icon, size: 18, color: foreground),
                const SizedBox(width: AppTokens.xs),
                Text(
                  active ? labelOn : labelOff,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Stands in for the power control while the board owns the relay.
class _BoardOwnedBanner extends StatelessWidget {
  const _BoardOwnedBanner({required this.accent, required this.enabled});

  final Color accent;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final FarmPalette palette = FarmPalette.of(context);

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.md),
      decoration: BoxDecoration(
        color: palette.surfaceSunken,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        border: Border.all(color: palette.hairline),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.auto_awesome,
            size: 16,
            color: enabled ? accent : palette.inkFaint,
          ),
          const SizedBox(width: AppTokens.xs),
          Expanded(
            child: Text(
              'Board controlled',
              style: theme.textTheme.titleSmall?.copyWith(
                color: enabled ? palette.inkSoft : palette.inkFaint,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}