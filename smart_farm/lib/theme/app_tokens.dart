import 'package:flutter/material.dart';

/// Geometry and motion constants shared by every surface in the app.
///
/// Keeping these in one place is what makes the layout feel deliberate: the
/// spacing scale is a fixed rhythm, the radii nest consistently, and every
/// transition uses one of three durations so the interface moves as a single
/// system rather than a collection of independent animations.
abstract final class AppTokens {
  // ---------------------------------------------------------------------------
  // Spacing scale
  // ---------------------------------------------------------------------------

  /// Hairline gap, e.g. between an icon and its label.
  static const double xxs = 4;

  /// Tight gap, e.g. icon to text inside a chip.
  static const double xs = 8;

  /// Default gap between related elements.
  static const double sm = 12;

  /// Default card padding.
  static const double md = 16;

  /// Gap between cards in a grid.
  static const double lg = 20;

  /// Gap between page sections.
  static const double xl = 28;

  /// Lead-in above a whole page region.
  static const double xxl = 40;

  // ---------------------------------------------------------------------------
  // Radii
  // ---------------------------------------------------------------------------

  /// Small chips and icon tiles.
  static const double radiusSm = 12;

  /// Controls such as buttons and toggles.
  static const double radiusMd = 16;

  /// Standard cards.
  static const double radiusLg = 22;

  /// Hero cards and sheets.
  static const double radiusXl = 28;

  /// Fully rounded ends for pills and badges.
  static const double radiusPill = 999;

  // ---------------------------------------------------------------------------
  // Motion
  // ---------------------------------------------------------------------------

  /// Colour and size changes that should feel instant.
  static const Duration instant = Duration(milliseconds: 140);

  /// The default transition: toggles, chips, expanding panels.
  static const Duration quick = Duration(milliseconds: 260);

  /// Gauge sweeps and value counters.
  static const Duration measured = Duration(milliseconds: 520);

  /// Page-level and layout transitions.
  static const Duration slow = Duration(milliseconds: 720);

  /// Standard easing. Fast out, gentle in: responsive without feeling bouncy.
  static const Curve curve = Curves.easeOutCubic;

  /// For elements that should overshoot slightly, such as the power toggle.
  static const Curve curveSpring = Curves.easeOutBack;

  /// Symmetric easing, for loops such as a running pump's glow.
  static const Curve curvePulse = Curves.easeInOutSine;

  // ---------------------------------------------------------------------------
  // Layout
  // ---------------------------------------------------------------------------

  /// The dashboard stops widening past this and centres instead, so the
  /// layout never stretches into unreadable full-bleed rows on a desktop
  /// window or a wall-mounted tablet in landscape.
  static const double contentMaxWidth = 1200;

  /// Above this width the shell swaps its bottom navigation for a rail.
  static const double railBreakpoint = 900;

  /// Gutter used on wide layouts, where cards sit beside one another.
  static const double gutter = 20;

  /// Tabular figures keep a live numeric readout from shifting sideways as its
  /// digits change once per second.
  static const List<FontFeature> tabularFigures = <FontFeature>[
    FontFeature.tabularFigures(),
  ];
}