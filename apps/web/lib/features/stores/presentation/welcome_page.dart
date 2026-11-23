import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app_services.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/kpop_components.dart';
import '../../../core/widgets/theme_toggle.dart';
import '../../../l10n/app_localizations.dart';
import '../../agent/presentation/kiu_bubble.dart';
import '../../agent/presentation/kiu_illustration.dart';

/// One screen, one intention: brand, Kiu, a short promise, "create my store"
/// and a way back in. It fits a phone without scrolling; it only scrolls when
/// the viewport is too short (landscape, keyboard, very large text).
class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return KPopScaffold(
      body: LayoutBuilder(
        builder: (context, viewport) {
          final wide = viewport.maxWidth >= KPopBreakpoint.medium;
          // At least one viewport tall, taller only when the content needs it
          // (landscape, very large text): then, and only then, it scrolls.
          // IntrinsicHeight sits under the max-width box so text is measured
          // at its real width.
          return SingleChildScrollView(
            key: const Key('welcome-scroll'),
            child: PageBody(
              // Tablets in portrait keep the phone composition, centred.
              maxWidth: wide ? 1180 : 560,
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: viewport.maxHeight),
                child: IntrinsicHeight(
                  child: wide
                      ? _Wide(services: services)
                      : _Compact(services: services),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.services});
  final AppServices services;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: KPopSpace.sm),
    child: Row(
      children: [
        const Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: KiuPopLogo(size: 40),
          ),
        ),
        ThemeToggle(controller: services.theme),
      ],
    ),
  );
}

class _Promise extends StatelessWidget {
  const _Promise({required this.large, this.tight = false});
  final bool large;
  final bool tight;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: large
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        Semantics(
          header: true,
          child: Text(
            l10n.tagline,
            textAlign: large ? TextAlign.start : TextAlign.center,
            style: large
                ? theme.textTheme.displayMedium
                : tight
                ? theme.textTheme.headlineSmall
                : theme.textTheme.headlineMedium,
          ),
        ),
        SizedBox(height: tight ? KPopSpace.xs : KPopSpace.sm),
        Text(
          l10n.welcomeLead,
          textAlign: large ? TextAlign.start : TextAlign.center,
          style:
              (large ? theme.textTheme.bodyLarge : theme.textTheme.bodyMedium)
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.services, required this.stretch});
  final AppServices services;
  final bool stretch;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final create = KPopButton(
      key: const Key('cta-kiu'),
      onPressed: () => context.go('/kiu'),
      icon: Icons.auto_awesome_rounded,
      label: l10n.createStoreCta,
      expand: stretch,
    );
    final enter = KPopButton(
      tone: KPopButtonTone.text,
      onPressed: () => context.go(
        services.auth.currentUser != null ? '/mi-tienda' : '/entrar',
      ),
      label: l10n.haveStoreCta,
      expand: stretch,
    );
    if (stretch) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          create,
          const SizedBox(height: KPopSpace.xxs),
          enter,
        ],
      );
    }
    return Wrap(
      spacing: KPopSpace.sm,
      runSpacing: KPopSpace.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [create, enter],
    );
  }
}

class _Compact extends StatelessWidget {
  const _Compact({required this.services});
  final AppServices services;

  @override
  Widget build(BuildContext context) {
    // Short phones (≈ 640 dp) get tighter rhythm and a smaller headline so the
    // whole intention still fits on one screen.
    final tight = MediaQuery.sizeOf(context).height < 700;
    final gap = tight ? KPopSpace.md : KPopSpace.lg;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TopBar(services: services),
        SizedBox(height: tight ? KPopSpace.xs : KPopSpace.md),
        // The stage takes whatever height is left; it never drops below a
        // readable size, and then the page scrolls instead of clipping.
        Expanded(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: tight ? 140 : 168),
            child: const KiuIllustration(mood: KiuMood.greeting),
          ),
        ),
        SizedBox(height: gap),
        _Promise(large: false, tight: tight),
        SizedBox(height: gap),
        _Actions(services: services, stretch: true),
        SizedBox(height: tight ? KPopSpace.xxs : KPopSpace.sm),
      ],
    );
  }
}

class _Wide extends StatelessWidget {
  const _Wide({required this.services});
  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TopBar(services: services),
        Expanded(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 360),
            child: Row(
              children: [
                Expanded(
                  flex: 11,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _Promise(large: true),
                      const SizedBox(height: KPopSpace.xl),
                      _Actions(services: services, stretch: false),
                    ],
                  ),
                ),
                const SizedBox(width: KPopSpace.xxl),
                Expanded(
                  flex: 10,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: 320,
                        maxHeight: 540,
                      ),
                      child: const AspectRatio(
                        aspectRatio: .92,
                        child: KiuIllustration(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: KPopSpace.lg),
      ],
    );
  }
}
