import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../state/farm_controller.dart';
import '../../theme/app_tokens.dart';
import '../../theme/farm_palette.dart';

/// Opens the sheet and returns the address to pin, or `null`.
///
/// A `null` result is ambiguous on its own — it means both "cancelled" and
/// "go back to discovery" — so those are distinguished by [GatewaySheetResult].
Future<GatewaySheetResult?> showGatewaySheet(
  BuildContext context, {
  required FarmController controller,
}) {
  return showModalBottomSheet<GatewaySheetResult>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext context) => _GatewaySheet(controller: controller),
  );
}

/// What the user asked the gateway sheet to do.
class GatewaySheetResult {
  const GatewaySheetResult.connect(this.address) : useDiscovery = false;

  const GatewaySheetResult.discovery()
      : address = '',
        useDiscovery = true;

  final String address;
  final bool useDiscovery;
}

class _GatewaySheet extends StatefulWidget {
  const _GatewaySheet({required this.controller});

  final FarmController controller;

  @override
  State<_GatewaySheet> createState() => _GatewaySheetState();
}

class _GatewaySheetState extends State<_GatewaySheet> {
  late final TextEditingController _field = TextEditingController(
    text: widget.controller.effectiveAddress ?? '',
  );

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _submit() {
    final String value = _field.text.trim();
    if (value.isEmpty) return;
    Navigator.of(context).pop(GatewaySheetResult.connect(value));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final FarmPalette palette = FarmPalette.of(context);
    final bool pinned = widget.controller.usingManualAddress;

    return Padding(
      // Lift the sheet clear of the keyboard so the Connect button stays
      // reachable while the address is being typed.
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTokens.lg,
            0,
            AppTokens.lg,
            AppTokens.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Gateway address', style: theme.textTheme.titleLarge),
              const SizedBox(height: AppTokens.xxs),
              Text(
                pinned
                    ? 'Pinned to ${widget.controller.effectiveAddress}.'
                    : 'Using mDNS discovery (_smartfarm._tcp).',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: palette.inkSoft,
                ),
              ),
              const SizedBox(height: AppTokens.md),
              TextField(
                controller: _field,
                autofocus: true,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.go,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.deny(RegExp(r'\s')),
                ],
                decoration: InputDecoration(
                  labelText: 'Host or host:port',
                  hintText:
                      '192.168.8.74:${FarmController.defaultPort}',
                  prefixIcon: const Icon(Icons.dns_outlined, size: 19),
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: AppTokens.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(Icons.info_outline_rounded,
                      size: 14, color: palette.inkFaint),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      'The port defaults to ${FarmController.defaultPort}. '
                      'A .local hostname only works on devices that can '
                      'resolve it — on Windows, use the IP address.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: palette.inkFaint,
                        fontSize: 11.5,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTokens.lg),
              Row(
                children: <Widget>[
                  if (pinned) ...<Widget>[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).pop(
                          const GatewaySheetResult.discovery(),
                        ),
                        icon: const Icon(Icons.radar_rounded, size: 18),
                        label: const Text('Use mDNS'),
                      ),
                    ),
                    const SizedBox(width: AppTokens.sm),
                  ],
                  Expanded(
                    child: FilledButton(
                      onPressed: _submit,
                      child: const Text('Connect'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}