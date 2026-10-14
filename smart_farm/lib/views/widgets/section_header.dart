import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';
import '../../theme/farm_palette.dart';

/// A heading for a group of cards, with an optional caption and trailing slot.
///
/// The old dashboard used bare uppercase text as a divider, which gave the eye
/// nothing to hold on to. Pairing the title with a sentence explaining the
/// section turns a scroll break into an instruction.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.caption,
    this.trailing,
    this.icon,
  });

  final String title;

  /// One line explaining what the section is for.
  final String? caption;

  final Widget? trailing;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final FarmPalette palette = FarmPalette.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, size: 16, color: palette.inkFaint),
            ),
            const SizedBox(width: AppTokens.xs),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: theme.textTheme.titleMedium),
                if (caption != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    caption!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: palette.inkFaint,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...<Widget>[
            const SizedBox(width: AppTokens.sm),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// Centres and pads a scrolling page, and stops it stretching into unreadable
/// full-bleed rows on a desktop window.
///
/// Both tabs share this so the two pages align on exactly the same gutter, and
/// so switching tabs does not shift the content sideways.
class PageBody extends StatelessWidget {
  const PageBody({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.fromLTRB(
      AppTokens.md,
      AppTokens.md,
      AppTokens.md,
      AppTokens.xxl,
    ),
  });

  final List<Widget> children;

  /// Overridden by the shell to add the gutter beside a navigation rail.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppTokens.contentMaxWidth),
        child: ListView(
          padding: padding,
          physics: const AlwaysScrollableScrollPhysics(),
          children: children,
        ),
      ),
    );
  }
}

/// Vertical rhythm between page sections.
class SectionGap extends StatelessWidget {
  const SectionGap({super.key, this.height = AppTokens.xl});

  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(height: height);
}