import 'package:flutter/material.dart';

import '../../services/websocket_service.dart';
import '../../theme/app_tokens.dart';
import '../../theme/farm_palette.dart';
import 'state_badge.dart';

/// The single place the app says how the link is doing.
///
/// The old dashboard reported connection state twice — a coloured label in the
/// app bar and a banner below it — and the two could disagree. This collapses
/// both into one bar that carries the whole story: the state, why it is in that
/// state, which gateway it is talking to, and how fresh the last frame was.
class ConnectionBar extends StatelessWidget {
  const ConnectionBar({
    super.key,
    required this.link,
    required this.message,
    required this.gateway,
    required this.lastFrameAt,
    required this.frameError,
    required this.hostnameOnly,
    required this.onRetry,
    required this.onConfigure,
  });

  final LinkState link;

  /// Plain-language status, e.g. `Scanning for the gateway…`.
  final String message;

  /// The gateway address being dialled, empty until one is resolved.
  final String gateway;

  final DateTime? lastFrameAt;

  /// Description of the most recent malformed frame, if any.
  final String frameError;

  /// Whether the gateway was reached through a name Windows cannot resolve.
  final bool hostnameOnly;

  final VoidCallback onRetry;

  final VoidCallback onConfigure;

  @override
  Widget build(BuildContext context) {
    final FarmPalette palette = FarmPalette.of(context);
    final bool busy = link == LinkState.discovering ||
        link == LinkState.connecting ||
        link == LinkState.reconnecting;
    final bool online = link == LinkState.online;

    final Color tone = online
        ? palette.online
        : (busy ? palette.warning : palette.danger);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                _StatusDot(online: online, busy: busy, tone: tone),
                const SizedBox(width: AppTokens.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              online ? 'Live' : message,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (online) ...<Widget>[
                            const SizedBox(width: AppTokens.xs),
                            Text(
                              _relative(lastFrameAt),
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: palette.inkFaint,
                                    letterSpacing: 0.2,
                                  ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 1),
                      Text(
                        _subtitle(context),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: palette.inkFaint,
                              fontSize: 11.5,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppTokens.xs),
                // Only the retry action lives here. Opening the gateway sheet is
                // the app bar's job; a second copy of that button inside the
                // status card just made the connection look like it had two
                // settings.
                _BarAction(
                  icon: Icons.refresh_rounded,
                  tooltip: 'Scan again',
                  onPressed: busy ? null : onRetry,
                ),
              ],
            ),
            if (hostnameOnly || frameError.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppTokens.sm),
              _Notice(
                message: hostnameOnly
                    ? 'Connected by hostname. Windows cannot resolve a .local '
                        'name, so this link can drop. Pin the IP to be safe.'
                    : frameError,
                color: palette.warning,
                action: hostnameOnly ? 'Pin address' : null,
                onAction: hostnameOnly ? onConfigure : null,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _subtitle(BuildContext context) {
    if (gateway.isEmpty) return 'Discovering _smartfarm._tcp';
    return '$gateway · port ${_portOf(gateway)}';
  }

  static int _portOf(String display) {
    final int colon = display.lastIndexOf(':');
    if (colon < 0) return 8765;
    return int.tryParse(display.substring(colon + 1)) ?? 8765;
  }

  /// "just now" / "4s ago" / "2m ago", so a stalled feed is obvious.
  static String _relative(DateTime? then) {
    if (then == null) return 'awaiting first frame';
    final Duration delta = DateTime.now().difference(then);
    if (delta.inSeconds < 2) return 'just now';
    if (delta.inSeconds < 60) return '${delta.inSeconds}s ago';
    return '${delta.inMinutes}m ago';
  }
}

/// The breathing dot that opens the bar.
class _StatusDot extends StatelessWidget {
  const _StatusDot({
    required this.online,
    required this.busy,
    required this.tone,
  });

  final bool online;
  final bool busy;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final FarmPalette palette = FarmPalette.of(context);
    final Widget dot = PulseDot(
      color: tone,
      size: 9,
      // Both states are worth watching: one means water is flowing, the other
      // that the app is still trying.
      active: online || busy,
      period: online
          ? const Duration(milliseconds: 1800)
          : const Duration(milliseconds: 1100),
    );

    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: FarmPalette.tint(tone, 0.12),
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      ),
      child: online || busy
          ? dot
          : Icon(Icons.cloud_off_rounded, size: 17, color: palette.inkFaint),
    );
  }
}

/// Square icon button matching the bar's flat treatment.
class _BarAction extends StatelessWidget {
  const _BarAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final FarmPalette palette = FarmPalette.of(context);

    return Tooltip(
      message: tooltip,
      child: Padding(
        padding: const EdgeInsets.only(left: 2),
        child: Material(
          borderRadius: BorderRadius.circular(AppTokens.radiusSm),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppTokens.radiusSm),
            onTap: onPressed,
            child: SizedBox(
              width: 38,
              height: 38,
              child: Icon(
                icon,
                size: 18,
                color: onPressed == null
                    ? palette.inkFaint.withValues(alpha: 0.5)
                    : palette.inkSoft,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Inline warning strip under the bar.
class _Notice extends StatelessWidget {
  const _Notice({
    required this.message,
    required this.color,
    this.action,
    this.onAction,
  });

  final String message;
  final Color color;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(AppTokens.sm, 9, 9, 9),
      decoration: BoxDecoration(
        color: FarmPalette.tint(color, 0.10),
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        border: Border.all(color: FarmPalette.tint(color, 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.warning_amber_rounded, size: 15, color: color),
          const SizedBox(width: AppTokens.xs),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: color,
                fontSize: 11.5,
                height: 1.35,
              ),
            ),
          ),
          if (action != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: color,
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: AppTokens.sm),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                action!,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}