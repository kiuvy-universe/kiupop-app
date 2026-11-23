import 'package:flutter/material.dart';

/// KiuPop design tokens (KPOP-UX-002): soft ceramic surfaces, pastel clay
/// tints and a kawaii-premium character. Every component reads these; no
/// raw values live in feature code.

abstract final class KPopSpace {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;
  static const touch = 48.0;
  static const gutter = 20.0;
}

abstract final class KPopRadius {
  static const chip = 999.0;
  static const control = 18.0;
  static const tile = 20.0;
  static const card = 28.0;
  static const hero = 36.0;
}

abstract final class KPopBreakpoint {
  static const compact = 600.0;
  static const medium = 840.0;
  static const expanded = 1200.0;
}

abstract final class KPopMotion {
  static const fast = Duration(milliseconds: 160);
  static const standard = Duration(milliseconds: 240);
  static const slow = Duration(milliseconds: 420);
  static const floatCycle = Duration(seconds: 10);
  static const greeting = Duration(milliseconds: 1100);
  static const pop = Duration(milliseconds: 960);
  static const celebrate = Duration(milliseconds: 1400);
  static const ease = Curves.easeOutCubic;
  static const emphasized = Curves.easeInOutCubicEmphasized;
  static const elastic = Curves.easeOutBack;
}

/// Pastel clay palette. Named tints are shared by both themes; the schemes
/// below choose readable foregrounds for each.
abstract final class KPopColors {
  static const cream = Color(0xFFFBF5EB);
  static const porcelain = Color(0xFFFFFDF8);
  static const peach = Color(0xFFFFD8AE);
  static const apricot = Color(0xFFF6B97D);
  static const lavender = Color(0xFFD9C8F4);
  static const bubblegum = Color(0xFFEFAED4);
  static const mint = Color(0xFFD7EBDC);
  static const babyBlue = Color(0xFFD5E6F5);
  static const butter = Color(0xFFF8E7A0);
  static const ink = Color(0xFF302C33);
  static const inkSoft = Color(0xFF5C5560);
  static const violet = Color(0xFF8F45CD);
  static const violetDeep = Color(0xFF7E3BB9);
  static const plum = Color(0xFF3B2A5C);
  static const night = Color(0xFF1C1920);
  static const nightSurface = Color(0xFF26222B);
}

/// Depth: a ceramic surface floats on two soft shadows (one wide and faint,
/// one tight) instead of a Material elevation overlay.
abstract final class KPopElevation {
  static List<BoxShadow> soft(Brightness brightness) =>
      brightness == Brightness.light
      ? const [
          BoxShadow(
            color: Color(0x12302C33),
            blurRadius: 28,
            offset: Offset(0, 12),
          ),
          BoxShadow(
            color: Color(0x0A302C33),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ]
      : const [
          BoxShadow(
            color: Color(0x55000000),
            blurRadius: 28,
            offset: Offset(0, 12),
          ),
        ];

  static List<BoxShadow> raised(Brightness brightness) =>
      brightness == Brightness.light
      ? const [
          BoxShadow(
            color: Color(0x1F302C33),
            blurRadius: 36,
            offset: Offset(0, 18),
          ),
          BoxShadow(
            color: Color(0x0F302C33),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ]
      : const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 36,
            offset: Offset(0, 18),
          ),
        ];
}

/// Pastel tints with a readable foreground for each theme.
enum KPopTint { peach, lavender, bubblegum, mint, babyBlue, butter }

extension KPopTintColors on KPopTint {
  Color background(ColorScheme scheme) {
    final dark = scheme.brightness == Brightness.dark;
    return switch (this) {
      KPopTint.peach => dark ? const Color(0xFF5A4024) : KPopColors.peach,
      KPopTint.lavender => dark ? const Color(0xFF4A3C6B) : KPopColors.lavender,
      KPopTint.bubblegum =>
        dark ? const Color(0xFF5A3450) : KPopColors.bubblegum,
      KPopTint.mint => dark ? const Color(0xFF2A4A38) : KPopColors.mint,
      KPopTint.babyBlue => dark ? const Color(0xFF2C4257) : KPopColors.babyBlue,
      KPopTint.butter => dark ? const Color(0xFF4E3F0A) : KPopColors.butter,
    };
  }

  Color foreground(ColorScheme scheme) {
    final dark = scheme.brightness == Brightness.dark;
    return switch (this) {
      KPopTint.peach =>
        dark ? const Color(0xFFFFE4C7) : const Color(0xFF5C3A14),
      KPopTint.lavender => dark ? const Color(0xFFE6DAFA) : KPopColors.plum,
      KPopTint.bubblegum =>
        dark ? const Color(0xFFFBDCEC) : const Color(0xFF5A1F42),
      KPopTint.mint => dark ? const Color(0xFFBFE5CC) : const Color(0xFF1F4A33),
      KPopTint.babyBlue =>
        dark ? const Color(0xFFC7DDF2) : const Color(0xFF1E3A57),
      KPopTint.butter =>
        dark ? const Color(0xFFF8E7A0) : const Color(0xFF4E3F0A),
    };
  }
}

/// KiuPop presentation theme. StorefrontRenderer applies each merchant's own
/// validated tokens on top of the shared typography and interaction defaults.
abstract final class AppTheme {
  static const paper = KPopColors.porcelain;
  static const background = KPopColors.cream;
  static const lavender = KPopColors.lavender;
  static const seed = KPopColors.violet;
  static const primary = KPopColors.ink;
  static const accent = KPopColors.bubblegum;
  static const ink = KPopColors.ink;
  static const border = Color(0xFFEADFD3);
  static const whatsapp = Color(0xFF12723E);
  static const String font = 'PlusJakartaSans';

  static Color success(ColorScheme scheme) =>
      scheme.brightness == Brightness.light
      ? const Color(0xFF1F7A4D)
      : const Color(0xFF8ADCAB);
  static const gap = KPopSpace.md;
  static const radius = KPopRadius.card;
  static const cardElevation = 0.0;

  static final _light = _build(
    const ColorScheme.light(
      primary: KPopColors.ink,
      onPrimary: KPopColors.porcelain,
      primaryContainer: KPopColors.lavender,
      onPrimaryContainer: KPopColors.plum,
      secondary: KPopColors.violetDeep,
      onSecondary: KPopColors.porcelain,
      secondaryContainer: KPopColors.peach,
      onSecondaryContainer: Color(0xFF5C3A14),
      tertiary: Color(0xFF9A2F6A),
      onTertiary: KPopColors.porcelain,
      tertiaryContainer: KPopColors.bubblegum,
      onTertiaryContainer: Color(0xFF5A1F42),
      error: Color(0xFFB42A3E),
      onError: KPopColors.porcelain,
      errorContainer: Color(0xFFFFE1E4),
      onErrorContainer: Color(0xFF6B1424),
      surface: KPopColors.porcelain,
      onSurface: KPopColors.ink,
      onSurfaceVariant: KPopColors.inkSoft,
      surfaceContainerLowest: Color(0xFFFFFFFF),
      surfaceContainerLow: KPopColors.cream,
      surfaceContainer: Color(0xFFF5ECDF),
      surfaceContainerHigh: Color(0xFFEFE4D4),
      surfaceContainerHighest: Color(0xFFE8DBC8),
      outline: Color(0xFF8F8389),
      outlineVariant: border,
      shadow: KPopColors.ink,
      inverseSurface: KPopColors.ink,
      onInverseSurface: KPopColors.cream,
    ),
  );

  static final _dark = _build(
    const ColorScheme.dark(
      primary: KPopColors.peach,
      onPrimary: Color(0xFF3A2A14),
      primaryContainer: Color(0xFF4A3C6B),
      onPrimaryContainer: Color(0xFFE6DAFA),
      secondary: Color(0xFFD9B8FF),
      onSecondary: Color(0xFF38145D),
      secondaryContainer: Color(0xFF5A4024),
      onSecondaryContainer: Color(0xFFFFE4C7),
      tertiary: Color(0xFFF7B8D8),
      onTertiary: Color(0xFF52203E),
      tertiaryContainer: Color(0xFF5A3450),
      onTertiaryContainer: Color(0xFFFBDCEC),
      error: Color(0xFFFFB3B8),
      onError: Color(0xFF5A1A24),
      errorContainer: Color(0xFF5A2630),
      onErrorContainer: Color(0xFFFFDADC),
      surface: KPopColors.nightSurface,
      onSurface: Color(0xFFF4EEE6),
      onSurfaceVariant: Color(0xFFC9C0C7),
      surfaceContainerLowest: Color(0xFF16131A),
      surfaceContainerLow: KPopColors.night,
      surfaceContainer: Color(0xFF2C2731),
      surfaceContainerHigh: Color(0xFF352F3B),
      surfaceContainerHighest: Color(0xFF3E3745),
      outline: Color(0xFF8E868D),
      outlineVariant: Color(0xFF3F3843),
      shadow: Color(0xFF000000),
      inverseSurface: Color(0xFFF4EEE6),
      onInverseSurface: KPopColors.night,
    ),
  );

  static ThemeData light() => _light;
  static ThemeData dark() => _dark;

  static ThemeData _build(ColorScheme scheme) {
    final text = _textTheme(scheme);
    const pill = StadiumBorder();
    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(KPopRadius.control),
    );
    final outline = OutlineInputBorder(
      borderRadius: BorderRadius.circular(KPopRadius.control),
      borderSide: BorderSide(color: scheme.outlineVariant),
    );
    const minSize = Size(KPopSpace.touch, 52);
    const buttonPadding = EdgeInsets.symmetric(
      horizontal: KPopSpace.lg,
      vertical: KPopSpace.sm,
    );
    WidgetStateProperty<BorderSide?> focusRing(Color color) =>
        WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.focused)
              ? BorderSide(color: color, width: 2)
              : null,
        );
    return ThemeData(
      colorScheme: scheme,
      fontFamily: font,
      textTheme: text,
      scaffoldBackgroundColor: scheme.surfaceContainerLow,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      focusColor: scheme.secondary.withValues(alpha: .16),
      splashFactory: InkSparkle.splashFactory,
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
      cardTheme: CardThemeData(
        elevation: cardElevation,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style:
            FilledButton.styleFrom(
              minimumSize: minSize,
              padding: buttonPadding,
              shape: pill,
              textStyle: text.labelLarge,
              elevation: 0,
            ).copyWith(
              side: focusRing(scheme.secondary),
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.disabled)
                    ? scheme.onSurface.withValues(alpha: .10)
                    : scheme.primary,
              ),
              foregroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.disabled)
                    ? scheme.onSurface.withValues(alpha: .38)
                    : scheme.onPrimary,
              ),
            ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style:
            OutlinedButton.styleFrom(
              minimumSize: minSize,
              padding: buttonPadding,
              shape: pill,
              textStyle: text.labelLarge,
              foregroundColor: scheme.onSurface,
              backgroundColor: scheme.surface,
            ).copyWith(
              side: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.disabled)
                    ? BorderSide(color: scheme.outlineVariant)
                    : states.contains(WidgetState.focused)
                    ? BorderSide(color: scheme.secondary, width: 2)
                    : BorderSide(color: scheme.outline.withValues(alpha: .6)),
              ),
            ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: minSize,
          shape: pill,
          textStyle: text.labelLarge,
          foregroundColor: scheme.secondary,
        ).copyWith(side: focusRing(scheme.secondary)),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size.square(KPopSpace.touch),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(shape: pill),
      ),
      chipTheme: ChipThemeData(
        labelStyle: text.labelLarge?.copyWith(color: scheme.onSurface),
        padding: const EdgeInsets.symmetric(
          horizontal: KPopSpace.sm,
          vertical: KPopSpace.sm,
        ),
        backgroundColor: scheme.surface,
        side: BorderSide(color: scheme.outlineVariant),
        shape: pill,
        elevation: 0,
        pressElevation: 0,
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: scheme.surface,
        border: outline,
        enabledBorder: outline,
        focusedBorder: outline.copyWith(
          borderSide: BorderSide(color: scheme.secondary, width: 2),
        ),
        errorBorder: outline.copyWith(
          borderSide: BorderSide(color: scheme.error, width: 1.5),
        ),
        focusedErrorBorder: outline.copyWith(
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: KPopSpace.gutter,
          vertical: KPopSpace.md,
        ),
        hintStyle: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
        labelStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        modalBackgroundColor: scheme.surface,
        constraints: const BoxConstraints(maxWidth: 640),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(KPopRadius.hero),
          ),
        ),
        showDragHandle: true,
        dragHandleColor: scheme.outlineVariant,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KPopRadius.card),
        ),
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyLarge?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: text.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KPopRadius.control),
        ),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: text.titleLarge,
        iconTheme: IconThemeData(color: scheme.onSurface),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        elevation: 0,
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        indicatorShape: pill,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => text.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: states.contains(WidgetState.selected)
                ? scheme.onSurface
                : scheme.onSurfaceVariant,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? scheme.onPrimaryContainer
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 0,
        highlightElevation: 0,
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: pill,
        extendedTextStyle: text.labelLarge,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.secondary,
        linearTrackColor: scheme.surfaceContainerHigh,
        circularTrackColor: scheme.surfaceContainerHigh,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.onPrimary
              : scheme.outline,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.surfaceContainerHigh,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      listTileTheme: ListTileThemeData(
        shape: controlShape,
        iconColor: scheme.onSurfaceVariant,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(KPopSpace.sm),
        ),
        textStyle: text.bodySmall?.copyWith(color: scheme.onInverseSurface),
      ),
    );
  }

  static TextTheme _textTheme(ColorScheme scheme) {
    final base = Typography.material2021().black.apply(
      fontFamily: font,
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );
    TextStyle? heading(TextStyle? style, FontWeight weight, double size) =>
        style?.copyWith(
          fontSize: size,
          fontWeight: weight,
          letterSpacing: size * -.03,
          height: 1.12,
        );
    return base.copyWith(
      displayLarge: heading(base.displayLarge, FontWeight.w800, 52),
      displayMedium: heading(base.displayMedium, FontWeight.w800, 42),
      displaySmall: heading(base.displaySmall, FontWeight.w800, 34),
      headlineLarge: heading(base.headlineLarge, FontWeight.w800, 30),
      headlineMedium: heading(base.headlineMedium, FontWeight.w800, 26),
      headlineSmall: heading(base.headlineSmall, FontWeight.w800, 22),
      titleLarge: heading(base.titleLarge, FontWeight.w800, 20),
      titleMedium: base.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
      titleSmall: base.titleSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
      bodyLarge: base.bodyLarge?.copyWith(height: 1.5, letterSpacing: 0),
      bodyMedium: base.bodyMedium?.copyWith(height: 1.45, letterSpacing: 0),
      bodySmall: base.bodySmall?.copyWith(
        height: 1.4,
        letterSpacing: 0,
        color: scheme.onSurfaceVariant,
      ),
      labelLarge: base.labelLarge?.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
      labelMedium: base.labelMedium?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
    );
  }
}
