import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class KPopScaffold extends StatelessWidget {
  const KPopScaffold({
    super.key,
    required this.body,
    this.appBar,
    this.bottomNavigationBar,
    this.floatingActionButton,
  });

  final Widget body;
  final PreferredSizeWidget? appBar;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: appBar,
    bottomNavigationBar: bottomNavigationBar,
    floatingActionButton: floatingActionButton,
    body: SafeArea(child: body),
  );
}

/// A soft ceramic surface: porcelain fill, hairline border and two diffuse
/// shadows. The building block for cards, panels and composers.
class KPopSurface extends StatelessWidget {
  const KPopSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(KPopSpace.lg),
    this.color,
    this.radius = KPopRadius.card,
    this.raised = false,
    this.flat = false,
    this.onTap,
    this.clip = Clip.antiAlias,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final double radius;
  final bool raised;

  /// No shadow: for surfaces nested inside another surface.
  final bool flat;
  final VoidCallback? onTap;
  final Clip clip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shape = BorderRadius.circular(radius);
    final fill = color ?? scheme.surface;
    final content = Padding(padding: padding, child: child);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: shape,
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: flat
            ? null
            : raised
            ? KPopElevation.raised(scheme.brightness)
            : KPopElevation.soft(scheme.brightness),
      ),
      child: Material(
        color: Colors.transparent,
        clipBehavior: clip,
        shape: RoundedRectangleBorder(borderRadius: shape),
        child: onTap == null ? content : InkWell(onTap: onTap, child: content),
      ),
    );
  }
}

/// Backwards-compatible card used by forms, chat and admin.
class KPopCard extends StatelessWidget {
  const KPopCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(KPopSpace.lg),
    this.color,
    this.flat = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final bool flat;

  @override
  Widget build(BuildContext context) =>
      KPopSurface(padding: padding, color: color, flat: flat, child: child);
}

/// A pastel clay tile: tinted block with a leading icon bubble, a label and
/// an optional line of detail (reference 1 list rows).
class KPopClayTile extends StatelessWidget {
  const KPopClayTile({
    super.key,
    required this.tint,
    required this.label,
    this.icon,
    this.subtitle,
  });

  final KPopTint tint;
  final String label;
  final String? subtitle;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fg = tint.foreground(scheme);
    final bg = tint.background(scheme);
    final row = Padding(
      padding: const EdgeInsets.fromLTRB(
        KPopSpace.sm,
        KPopSpace.sm,
        KPopSpace.md,
        KPopSpace.sm,
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            KPopIconBubble(icon: icon!, color: fg, background: scheme.surface),
            const SizedBox(width: KPopSpace.sm),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.titleSmall?.copyWith(color: fg),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: fg.withValues(alpha: .82),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(KPopRadius.tile),
      ),
      child: row,
    );
  }
}

/// Round pastel badge with an icon (reference 3 icon chips).
class KPopIconBubble extends StatelessWidget {
  const KPopIconBubble({
    super.key,
    required this.icon,
    this.tint,
    this.color,
    this.background,
    this.size = 40,
  });

  final IconData icon;
  final KPopTint? tint;
  final Color? color;
  final Color? background;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg =
        background ?? tint?.background(scheme) ?? scheme.primaryContainer;
    final fg = color ?? tint?.foreground(scheme) ?? scheme.onPrimaryContainer;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Icon(icon, size: size * .5, color: fg),
    );
  }
}

enum KPopButtonTone { primary, tonal, outlined, text }

class KPopButton extends StatelessWidget {
  const KPopButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.secondary = false,
    this.tone,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// Legacy flag: `secondary: true` renders the outlined tone.
  final bool secondary;
  final KPopButtonTone? tone;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Text(label, textAlign: TextAlign.center);
    final glyph = icon == null ? null : Icon(icon, size: 20);
    final resolved =
        tone ?? (secondary ? KPopButtonTone.outlined : KPopButtonTone.primary);
    final press = onPressed;
    final tonal = FilledButton.styleFrom(
      backgroundColor: scheme.secondaryContainer,
      foregroundColor: scheme.onSecondaryContainer,
    );
    final Widget button = switch (resolved) {
      KPopButtonTone.primary =>
        glyph == null
            ? FilledButton(onPressed: press, child: text)
            : FilledButton.icon(onPressed: press, icon: glyph, label: text),
      KPopButtonTone.tonal =>
        glyph == null
            ? FilledButton(onPressed: press, style: tonal, child: text)
            : FilledButton.icon(
                onPressed: press,
                style: tonal,
                icon: glyph,
                label: text,
              ),
      KPopButtonTone.outlined =>
        glyph == null
            ? OutlinedButton(onPressed: press, child: text)
            : OutlinedButton.icon(onPressed: press, icon: glyph, label: text),
      KPopButtonTone.text =>
        glyph == null
            ? TextButton(onPressed: press, child: text)
            : TextButton.icon(onPressed: press, icon: glyph, label: text),
    };
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// Pastel pill chip for quick replies and filters.
class KPopChip extends StatelessWidget {
  const KPopChip({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.tint = KPopTint.lavender,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final KPopTint tint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = tint.foreground(scheme);
    return ActionChip(
      avatar: icon == null ? null : Icon(icon, size: 18, color: fg),
      label: Text(label),
      labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(color: fg),
      backgroundColor: tint.background(scheme),
      side: BorderSide.none,
      onPressed: onPressed,
    );
  }
}

/// Quiet notice (test modes, hints) on a pastel tint.
class KPopBanner extends StatelessWidget {
  const KPopBanner({
    super.key,
    required this.text,
    this.icon = Icons.info_outline_rounded,
    this.tint = KPopTint.butter,
  });

  final String text;
  final IconData icon;
  final KPopTint tint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = tint.foreground(scheme);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KPopSpace.md,
        vertical: KPopSpace.sm,
      ),
      decoration: BoxDecoration(
        color: tint.background(scheme),
        borderRadius: BorderRadius.circular(KPopRadius.tile),
      ),
      child: Row(
        children: [
          Icon(icon, color: fg, size: 20),
          const SizedBox(width: KPopSpace.sm),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: fg),
            ),
          ),
        ],
      ),
    );
  }
}

class KPopInput extends StatelessWidget {
  const KPopInput({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.onSubmitted,
    required this.enabled,
    this.maxLines = 3,
    this.borderless = false,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final VoidCallback onSubmitted;
  final bool enabled;
  final int maxLines;

  /// Inside a composer surface the field draws no border of its own.
  final bool borderless;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    focusNode: focusNode,
    minLines: 1,
    maxLines: maxLines,
    maxLength: 1000,
    enabled: enabled,
    textInputAction: TextInputAction.send,
    onSubmitted: (_) => onSubmitted(),
    decoration: InputDecoration(
      hintText: hint,
      counterText: '',
      filled: !borderless,
      border: borderless ? InputBorder.none : null,
      enabledBorder: borderless ? InputBorder.none : null,
      focusedBorder: borderless ? InputBorder.none : null,
      disabledBorder: borderless ? InputBorder.none : null,
      contentPadding: borderless
          ? const EdgeInsets.symmetric(
              horizontal: KPopSpace.sm,
              vertical: KPopSpace.sm,
            )
          : null,
    ),
  );
}

abstract final class KPopSheet {
  static Future<T?> show<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    Color? backgroundColor,
  }) => showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: backgroundColor,
    builder: builder,
    sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
        ? AnimationStyle.noAnimation
        : const AnimationStyle(
            duration: KPopMotion.standard,
            reverseDuration: KPopMotion.fast,
          ),
  );
}
