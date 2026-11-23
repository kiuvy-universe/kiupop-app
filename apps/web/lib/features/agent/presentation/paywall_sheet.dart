import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/kpop_components.dart';
import '../../../l10n/app_localizations.dart';
import '../data/agent_models.dart';

/// Quiz-funnel paywall: the merchant already saw the finished store for free;
/// publishing it needs the monthly plan per active store. Test mode only: the
/// payment is simulated and no real money moves. Returns true once the plan is
/// active (the server re-checks it on publish).
abstract final class PaywallSheet {
  static Future<bool> show(
    BuildContext context, {
    required PaywallInfo paywall,
    required Future<ApiResult<PaywallInfo>> Function() pay,
  }) async {
    final ok = await KPopSheet.show<bool>(
      context: context,
      builder: (ctx) => _PaywallBody(paywall: paywall, pay: pay),
    );
    return ok ?? false;
  }
}

class _PaywallBody extends StatefulWidget {
  const _PaywallBody({required this.paywall, required this.pay});

  final PaywallInfo paywall;
  final Future<ApiResult<PaywallInfo>> Function() pay;

  @override
  State<_PaywallBody> createState() => _PaywallBodyState();
}

class _PaywallBodyState extends State<_PaywallBody> {
  bool _paying = false;
  String? _error;

  Future<void> _pay() async {
    setState(() {
      _paying = true;
      _error = null;
    });
    final res = await widget.pay();
    if (!mounted) return;
    switch (res) {
      case ApiSuccess(:final value) when value.active:
        Navigator.of(context).pop(true);
      case ApiFailure(:final message):
        setState(() {
          _paying = false;
          _error = message ?? AppLocalizations.of(context).paywallFailed;
        });
      default:
        setState(() {
          _paying = false;
          _error = AppLocalizations.of(context).paywallFailed;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final price = widget.paywall.priceLabel;
    return SingleChildScrollView(
      key: const Key('paywall-sheet'),
      padding: const EdgeInsets.fromLTRB(
        KPopSpace.lg,
        KPopSpace.md,
        KPopSpace.lg,
        KPopSpace.lg,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.paywall.isTest)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    key: const Key('paywall-test-badge'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: KPopSpace.sm,
                      vertical: KPopSpace.xxs,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      l10n.paywallTestBadge,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onTertiaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: KPopSpace.md),
              Semantics(
                header: true,
                child: Text(
                  l10n.paywallTitle,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: KPopSpace.xs),
              Text(
                l10n.paywallLead,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: KPopSpace.md),
              KPopBanner(
                key: const Key('paywall-demo-notice'),
                text: l10n.paywallDemoNotice,
                icon: Icons.science_outlined,
              ),
              const SizedBox(height: KPopSpace.md),
              KPopSurface(
                color: KPopTint.lavender.background(scheme),
                padding: const EdgeInsets.all(KPopSpace.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.paywallPlanName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: KPopTint.lavender.foreground(scheme),
                      ),
                    ),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: price,
                            style: theme.textTheme.displaySmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: KPopTint.lavender.foreground(scheme),
                            ),
                          ),
                          TextSpan(
                            text: l10n.paywallPerMonth,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: KPopTint.lavender.foreground(scheme),
                            ),
                          ),
                        ],
                      ),
                      key: const Key('paywall-price'),
                    ),
                    Text(
                      l10n.paywallPriceNote,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: KPopTint.lavender.foreground(scheme),
                      ),
                    ),
                    const SizedBox(height: KPopSpace.md),
                    Text(
                      l10n.paywallIncludedTitle,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: KPopTint.lavender.foreground(scheme),
                      ),
                    ),
                    const SizedBox(height: KPopSpace.xs),
                    for (final item in [
                      l10n.paywallBenefitCatalog,
                      l10n.paywallBenefitLinks,
                      l10n.paywallBenefitCart,
                      l10n.paywallBenefitWhatsApp,
                      l10n.paywallBenefitAdmin,
                      l10n.paywallBenefitDesign,
                      l10n.paywallBenefitKiu,
                    ])
                      _Benefit(
                        text: item,
                        icon: Icons.check_circle_rounded,
                        color: KPopTint.lavender.foreground(scheme),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: KPopSpace.sm),
              KPopSurface(
                key: const Key('paywall-soon'),
                flat: true,
                color: scheme.surfaceContainer,
                padding: const EdgeInsets.all(KPopSpace.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.paywallSoonTitle,
                      style: theme.textTheme.labelLarge,
                    ),
                    const SizedBox(height: KPopSpace.xs),
                    for (final item in [
                      l10n.paywallSoonPayments,
                      l10n.paywallSoonIntegrations,
                    ])
                      _Benefit(
                        text: item,
                        icon: Icons.schedule_rounded,
                        color: scheme.onSurfaceVariant,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: KPopSpace.sm),
              Text(
                l10n.paywallFreeNote,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: KPopSpace.sm),
                Text(
                  _error!,
                  key: const Key('paywall-error'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.error,
                  ),
                ),
              ],
              const SizedBox(height: KPopSpace.lg),
              SizedBox(
                height: KPopSpace.touch,
                child: KPopButton(
                  key: const Key('paywall-pay'),
                  label: _paying ? l10n.paywallPaying : l10n.paywallSimulateCta,
                  icon: Icons.science_outlined,
                  onPressed: _paying ? null : _pay,
                ),
              ),
              const SizedBox(height: KPopSpace.xs),
              SizedBox(
                height: KPopSpace.touch,
                child: KPopButton(
                  key: const Key('paywall-later'),
                  label: l10n.paywallLater,
                  secondary: true,
                  onPressed: _paying
                      ? null
                      : () => Navigator.of(context).pop(false),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Benefit extends StatelessWidget {
  const _Benefit({required this.text, required this.icon, required this.color});
  final String text;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: KPopSpace.xs),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: KPopSpace.xs),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: color),
          ),
        ),
      ],
    ),
  );
}
