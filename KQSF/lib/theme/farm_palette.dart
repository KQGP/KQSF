import 'package:flutter/material.dart';

/// Every colour the interface paints, declared once for each brightness.
///
/// The dashboard is colour-coded by subsystem rather than by Material's
/// default scheme: soil, rain, temperature, humidity, pumps and the roof each
/// own a hue, and the same hue is used for that subsystem's icon, its gauge and
/// its running state. That makes a glance at the screen answer "is the
/// irrigation running?" without reading a single label.
///
/// Stored as a [ThemeExtension] so widgets resolve colours through
/// `Theme.of(context).extension<FarmPalette>()!` and never have to branch on
/// brightness themselves.
@immutable
class FarmPalette extends ThemeExtension<FarmPalette> {
  const FarmPalette({
    required this.canvas,
    required this.surface,
    required this.surfaceSunken,
    required this.hairline,
    required this.ink,
    required this.inkSoft,
    required this.inkFaint,
    required this.soil,
    required this.rain,
    required this.temperature,
    required this.humidity,
    required this.pump,
    required this.roof,
    required this.online,
    required this.warning,
    required this.danger,
  });

  // ---------------------------------------------------------------------------
  // Neutrals
  // ---------------------------------------------------------------------------

  /// Page background, a shade off the card colour so flat cards still read as
  /// separate surfaces without needing a shadow.
  final Color canvas;

  /// Card and sheet fill.
  final Color surface;

  /// Recessed fill for tracks, wells and inactive controls.
  final Color surfaceSunken;

  /// One-pixel separators and card outlines.
  final Color hairline;

  /// Primary text.
  final Color ink;

  /// Secondary text: units, captions, descriptions.
  final Color inkSoft;

  /// Tertiary text: timestamps, hints, disabled labels.
  final Color inkFaint;

  // ---------------------------------------------------------------------------
  // Subsystem accents
  // ---------------------------------------------------------------------------

  /// Soil moisture probe.
  final Color soil;

  /// Rain probe.
  final Color rain;

  /// Air temperature.
  final Color temperature;

  /// Air humidity.
  final Color humidity;

  /// Shared accent for both pump relays.
  final Color pump;

  /// Roof servo pair.
  final Color roof;

  // ---------------------------------------------------------------------------
  // Semantic states
  // ---------------------------------------------------------------------------

  /// Link is up, telemetry is arriving.
  final Color online;

  /// Something needs attention but nothing is broken.
  final Color warning;

  /// Link is down, or a command failed.
  final Color danger;

  /// Bright, flat palette on a cool off-white canvas.
  factory FarmPalette.light() => const FarmPalette(
    canvas: Color(0xFFF4F6FB),
    surface: Color(0xFFFFFFFF),
    surfaceSunken: Color(0xFFEDF0F7),
    hairline: Color(0xFFE2E7F0),
    ink: Color(0xFF0D1424),
    inkSoft: Color(0xFF5B6579),
    inkFaint: Color(0xFF98A1B2),
    soil: Color(0xFF21B567),
    rain: Color(0xFF2C9BF0),
    temperature: Color(0xFFF08C0A),
    humidity: Color(0xFF7C5CF5),
    pump: Color(0xFF00A5BF),
    roof: Color(0xFF5B5BD6),
    online: Color(0xFF12B76A),
    warning: Color(0xFFF08C0A),
    danger: Color(0xFFEE4433),
  );

  /// Vivid accents on deep slate, lifted so they stay legible against it.
  factory FarmPalette.dark() => const FarmPalette(
    canvas: Color(0xFF080B12),
    surface: Color(0xFF141A26),
    surfaceSunken: Color(0xFF1C2433),
    hairline: Color(0xFF242E40),
    ink: Color(0xFFF1F5FB),
    inkSoft: Color(0xFF98A3B8),
    inkFaint: Color(0xFF69758C),
    soil: Color(0xFF41D183),
    rain: Color(0xFF52B4F7),
    temperature: Color(0xFFFBBF24),
    humidity: Color(0xFFA78BFA),
    pump: Color(0xFF22D3EE),
    roof: Color(0xFF8B8BF8),
    online: Color(0xFF32D583),
    warning: Color(0xFFFBBF24),
    danger: Color(0xFFF97066),
  );

  /// Resolves the palette for the active theme.
  static FarmPalette of(BuildContext context) =>
      Theme.of(context).extension<FarmPalette>() ?? FarmPalette.light();

  /// A tinted fill for [color], used for icon chips and state badges.
  static Color tint(Color color, double strength) =>
      color.withValues(alpha: strength);

  @override
  FarmPalette copyWith({
    Color? canvas,
    Color? surface,
    Color? surfaceSunken,
    Color? hairline,
    Color? ink,
    Color? inkSoft,
    Color? inkFaint,
    Color? soil,
    Color? rain,
    Color? temperature,
    Color? humidity,
    Color? pump,
    Color? roof,
    Color? online,
    Color? warning,
    Color? danger,
  }) {
    return FarmPalette(
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      surfaceSunken: surfaceSunken ?? this.surfaceSunken,
      hairline: hairline ?? this.hairline,
      ink: ink ?? this.ink,
      inkSoft: inkSoft ?? this.inkSoft,
      inkFaint: inkFaint ?? this.inkFaint,
      soil: soil ?? this.soil,
      rain: rain ?? this.rain,
      temperature: temperature ?? this.temperature,
      humidity: humidity ?? this.humidity,
      pump: pump ?? this.pump,
      roof: roof ?? this.roof,
      online: online ?? this.online,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
    );
  }

  @override
  FarmPalette lerp(covariant FarmPalette? other, double t) {
    if (other == null) return this;
    return FarmPalette(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceSunken: Color.lerp(surfaceSunken, other.surfaceSunken, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      inkSoft: Color.lerp(inkSoft, other.inkSoft, t)!,
      inkFaint: Color.lerp(inkFaint, other.inkFaint, t)!,
      soil: Color.lerp(soil, other.soil, t)!,
      rain: Color.lerp(rain, other.rain, t)!,
      temperature: Color.lerp(temperature, other.temperature, t)!,
      humidity: Color.lerp(humidity, other.humidity, t)!,
      pump: Color.lerp(pump, other.pump, t)!,
      roof: Color.lerp(roof, other.roof, t)!,
      online: Color.lerp(online, other.online, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
    );
  }
}