import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../network/api_client.dart';
import '../theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import 'kpop_components.dart';

/// Kiuvy mark paired with the KiuPop wordmark.
class KiuPopLogo extends StatelessWidget {
  const KiuPopLogo({super.key, this.size = 40, this.showName = true});

  final double size;
  final bool showName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size * .3),
            boxShadow: KPopElevation.soft(theme.brightness),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(size * .3),
            child: Image.asset(
              'assets/brand/kiupop-mark.png',
              width: size,
              height: size,
              excludeFromSemantics: true,
            ),
          ),
        ),
        if (showName) ...[
          const SizedBox(width: KPopSpace.xs),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                'KiuPop',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Centers content with a readable max width and phone-friendly padding.
class PageBody extends StatelessWidget {
  const PageBody({
    super.key,
    required this.child,
    this.maxWidth = 640,
    this.heightFactor,
  });

  final Widget child;
  final double maxWidth;
  final double? heightFactor;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= KPopBreakpoint.compact;
    return Align(
      alignment: Alignment.topCenter,
      heightFactor: heightFactor,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: wide ? KPopSpace.lg : KPopSpace.gutter,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Friendly empty / error state: pastel icon bubble, title, reason and the
/// next action.
class MessageState extends StatelessWidget {
  const MessageState({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.actionLabel,
    this.onAction,
    this.tint = KPopTint.lavender,
  });

  final IconData icon;
  final String title;
  final String? body;
  final String? actionLabel;
  final VoidCallback? onAction;
  final KPopTint tint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(KPopSpace.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              KPopIconBubble(icon: icon, tint: tint, size: 72),
              const SizedBox(height: KPopSpace.md),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge,
              ),
              if (body != null) ...[
                const SizedBox(height: KPopSpace.xs),
                Text(
                  body!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: KPopSpace.lg),
                KPopButton(
                  label: actionLabel!,
                  onPressed: onAction,
                  tone: KPopButtonTone.tonal,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Maps any failure to a friendly, safe sentence (server message when present).
String failureMessage(BuildContext context, ApiFailure<Object?> f) {
  final l10n = AppLocalizations.of(context);
  if (f.message != null && f.message!.isNotEmpty) return f.message!;
  return switch (f.kind) {
    ApiFailureKind.unreachable => l10n.errorOffline,
    ApiFailureKind.timeout => l10n.errorTimeout,
    _ => l10n.errorGeneric,
  };
}

/// Shows a short floating message.
void showSnack(BuildContext context, String text, {bool error = false}) {
  final scheme = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? scheme.error : null,
      ),
    );
}

/// Product photo or a tasteful placeholder.
class ProductImage extends StatelessWidget {
  const ProductImage({
    super.key,
    required this.url,
    this.borderRadius = 0,
    this.placeholder,
  });

  final Uri? url;
  final double borderRadius;
  final Widget? placeholder;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fallback =
        placeholder ??
        ColoredBox(
          color: KPopTint.peach.background(scheme).withValues(alpha: .55),
          child: Center(
            child: Icon(
              Icons.local_florist_outlined,
              color: KPopTint.peach.foreground(scheme).withValues(alpha: .6),
              size: 36,
            ),
          ),
        );
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: url == null
          ? fallback
          : LayoutBuilder(
              builder: (context, bounds) {
                final displayWidth = bounds.maxWidth;
                final width = kIsWeb || !displayWidth.isFinite
                    ? null
                    : ((displayWidth *
                                      MediaQuery.devicePixelRatioOf(context) /
                                      160)
                                  .ceil() *
                              160)
                          .clamp(160, 1120);
                return Image.network(
                  url.toString(),
                  fit: BoxFit.cover,
                  cacheWidth: width,
                  excludeFromSemantics: true,
                  frameBuilder: (context, child, frame, synchronous) =>
                      frame != null || synchronous ? child : fallback,
                  errorBuilder: (_, _, _) => fallback,
                );
              },
            ),
    );
  }
}
