import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../data/storefront_models.dart';

/// Turns validated tokens into a Material theme. Shared by preview and public store.
ThemeData storefrontTheme(StoreTheme t) {
  final base = ColorScheme.fromSeed(seedColor: t.primary);
  final scheme = base.copyWith(
    primary: t.primary,
    onPrimary: t.onPrimary,
    secondary: t.accent,
    secondaryContainer: t.secondary,
    onSecondaryContainer: t.text,
    surface: t.surface,
    onSurface: t.text,
    onSurfaceVariant: t.muted,
    surfaceContainerLow: Color.alphaBlend(
      t.secondary.withValues(alpha: 0.28),
      t.surface,
    ),
  );
  final r = BorderRadius.circular(t.radius);
  final buttonShape = t.pillButtons
      ? const StadiumBorder()
      : RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(t.radius * 0.6),
        );
  final heading = switch (t.typographyStyle) {
    'elegant' => TextStyle(
      fontWeight: t.headingFontWeight,
      letterSpacing: 0.4,
      height: 1.1,
    ),
    'playful' => TextStyle(
      fontWeight: t.headingFontWeight,
      letterSpacing: -0.2,
      height: 1.05,
    ),
    _ => TextStyle(
      fontWeight: t.headingFontWeight,
      letterSpacing: -0.6,
      height: 1.05,
    ),
  };
  final text = AppTheme.light().textTheme.apply(
    bodyColor: t.text,
    displayColor: t.text,
  );
  return AppTheme.light().copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: t.background,
    textTheme: text.copyWith(
      displaySmall: text.displaySmall
          ?.merge(heading)
          .copyWith(fontSize: 34 * t.scale),
      headlineSmall: text.headlineSmall
          ?.merge(heading)
          .copyWith(fontSize: 24 * t.scale),
      titleLarge: text.titleLarge
          ?.merge(heading)
          .copyWith(fontSize: 20 * t.scale),
    ),
    cardTheme: CardThemeData(
      elevation: t.cardStyle == 'elevated' ? 1 : 0,
      shadowColor: t.primary.withValues(alpha: 0.12),
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      color: t.cardStyle == 'soft' ? scheme.surfaceContainerLow : t.surface,
      shape: RoundedRectangleBorder(
        borderRadius: r,
        side: t.cardStyle == 'outlined'
            ? BorderSide(color: t.muted.withValues(alpha: 0.25))
            : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 50),
        shape: buttonShape,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 50),
        shape: buttonShape,
        foregroundColor: t.primary,
        side: BorderSide(color: t.primary.withValues(alpha: 0.5)),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: t.secondary.withValues(alpha: 0.6),
      labelStyle: TextStyle(color: t.text, fontWeight: FontWeight.w600),
      side: BorderSide.none,
      shape: const StadiumBorder(),
    ),
  );
}
