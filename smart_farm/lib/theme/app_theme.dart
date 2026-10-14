import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_tokens.dart';
import 'farm_palette.dart';

/// Builds the app's two [ThemeData]s.
///
/// The styling brief is *flat*: nothing is elevated by a shadow. Separation
/// comes from a one-pixel [FarmPalette.hairline] outline and a fill that is a
/// shade lighter or darker than the canvas. Colour does the rest of the work.
abstract final class AppTheme {
  /// `useMaterial3` with a hand-tuned flat treatment.
  static ThemeData light() => _build(FarmPalette.light(), Brightness.light);

  static ThemeData dark() => _build(FarmPalette.dark(), Brightness.dark);

  static ThemeData _build(FarmPalette palette, Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: palette.soil,
      brightness: brightness,
    ).copyWith(
      primary: isDark ? palette.soil : const Color(0xFF12874C),
      onPrimary: isDark ? const Color(0xFF04180E) : Colors.white,
      surface: palette.canvas,
      onSurface: palette.ink,
      error: palette.danger,
      outline: palette.hairline,
    );

    final TextTheme text = _textTheme(palette, brightness);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: palette.canvas,
      canvasColor: palette.canvas,
      splashFactory: InkSparkle.splashFactory,
      textTheme: text,
      dividerTheme: DividerThemeData(
        color: palette.hairline,
        thickness: 1,
        space: 1,
      ),
      iconTheme: IconThemeData(color: palette.inkSoft, size: 20),
      extensions: <ThemeExtension<dynamic>>[palette],

      // -- App bar ------------------------------------------------------------
      appBarTheme: AppBarTheme(
        backgroundColor: palette.canvas,
        surfaceTintColor: Colors.transparent,
        foregroundColor: palette.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),

      // -- Flat cards ---------------------------------------------------------
      // `CardThemeData` is the Flutter 3.29+ replacement for `CardTheme`.
      cardTheme: CardThemeData(
        color: palette.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusLg),
          side: BorderSide(color: palette.hairline),
        ),
      ),

      // -- Controls -----------------------------------------------------------
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          elevation: 0,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: AppTokens.xl),
          textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          minimumSize: const Size(0, 44),
          textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.ink,
          minimumSize: const Size(0, 48),
          side: BorderSide(color: palette.hairline),
          textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) =>
              states.contains(WidgetState.selected)
                  ? scheme.onPrimary
                  : palette.inkFaint,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? scheme.primary
              : palette.surfaceSunken,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? Colors.transparent
              : palette.hairline,
        ),
        // A check in the thumb makes the on-state legible without relying on
        // colour alone.
        thumbIcon: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? Icon(Icons.check_rounded, size: 14, color: scheme.primary)
              : null,
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.primary,
        inactiveTrackColor: palette.surfaceSunken,
        thumbColor: scheme.primary,
        overlayColor: scheme.primary.withValues(alpha: 0.12),
        trackHeight: 6,
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: palette.surfaceSunken,
        circularTrackColor: palette.surfaceSunken,
      ),

      // -- Navigation ---------------------------------------------------------
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primary.withValues(alpha: 0.14),
        elevation: 0,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) => text.labelMedium?.copyWith(
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : palette.inkSoft,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) => IconThemeData(
            size: 22,
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : palette.inkSoft,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: palette.surface,
        indicatorColor: scheme.primary.withValues(alpha: 0.14),
        elevation: 0,
        selectedIconTheme: IconThemeData(size: 22, color: scheme.primary),
        unselectedIconTheme: IconThemeData(size: 22, color: palette.inkSoft),
        selectedLabelTextStyle: text.labelMedium?.copyWith(
          color: scheme.primary,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelTextStyle:
            text.labelMedium?.copyWith(color: palette.inkSoft),
      ),

      // -- Sheets and dialogs -------------------------------------------------
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: palette.surface,
        elevation: 0,
        showDragHandle: true,
        dragHandleColor: palette.hairline,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppTokens.radiusXl),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium?.copyWith(color: palette.inkSoft),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusXl),
          side: BorderSide(color: palette.hairline),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surfaceSunken,
        hintStyle: text.bodyMedium?.copyWith(color: palette.inkFaint),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppTokens.md,
          vertical: AppTokens.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          borderSide: BorderSide(color: palette.hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          borderSide: BorderSide(color: palette.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? palette.surfaceSunken : palette.ink,
        contentTextStyle: text.bodyMedium?.copyWith(
          color: isDark ? palette.ink : palette.canvas,
        ),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? palette.surfaceSunken : palette.ink,
          borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        ),
        textStyle: text.labelSmall?.copyWith(
          color: isDark ? palette.ink : palette.canvas,
        ),
      ),

      // -- Motion -------------------------------------------------------------
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }

  /// Tabular figures on the numeric styles, so readouts updated once a second
  /// do not shimmer as their digits change width.
  static TextTheme _textTheme(FarmPalette palette, Brightness brightness) {
    final TextTheme base = ThemeData(brightness: brightness).textTheme;

    return base
        .copyWith(
          headlineMedium: base.headlineMedium?.copyWith(
            color: palette.ink,
            fontWeight: FontWeight.w700,
            letterSpacing: -1.0,
            fontFeatures: AppTokens.tabularFigures,
          ),
          headlineSmall: base.headlineSmall?.copyWith(
            color: palette.ink,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            fontFeatures: AppTokens.tabularFigures,
          ),
          titleLarge: base.titleLarge?.copyWith(
            color: palette.ink,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
          titleMedium: base.titleMedium?.copyWith(
            color: palette.ink,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
          bodyMedium: base.bodyMedium?.copyWith(color: palette.inkSoft),
          bodySmall: base.bodySmall?.copyWith(color: palette.inkSoft),
          labelSmall: base.labelSmall?.copyWith(
            color: palette.inkFaint,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.9,
          ),
        )
        .apply(bodyColor: palette.ink, displayColor: palette.ink);
  }
}