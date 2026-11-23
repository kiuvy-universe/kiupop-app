import 'package:flutter/material.dart';

import '../../../core/format/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../../l10n/app_localizations.dart';
import '../data/cart.dart';

SliverGridDelegate catalogGrid(
  BuildContext context,
  double width, {
  required double spacing,
  required double height,
}) {
  final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
  final columns = width >= 1000
      ? 4
      : width >= 680
      ? (scale > 1.5 ? 2 : 3)
      : width < 328 || (scale > 1.45 && width < 580)
      ? 1
      : 2;
  return SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: columns,
    crossAxisSpacing: spacing,
    mainAxisSpacing: spacing,
    mainAxisExtent: height + ((scale - 1) * 160).clamp(0, 160),
  );
}

class CartSummaryButton extends StatelessWidget {
  const CartSummaryButton({
    super.key,
    required this.cart,
    required this.onOpen,
  });

  final Cart cart;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: cart,
    builder: (context, _) {
      if (cart.isEmpty) return const SizedBox.shrink();
      final l10n = AppLocalizations.of(context);
      return SafeArea(
        top: false,
        child: PageBody(
          maxWidth: 640,
          heightFactor: 1,
          child: Padding(
            padding: const EdgeInsets.only(
              bottom: KPopSpace.sm,
              top: KPopSpace.xs,
            ),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('open-cart'),
                onPressed: onOpen,
                child: OverflowBar(
                  alignment: MainAxisAlignment.spaceBetween,
                  overflowAlignment: OverflowBarAlignment.start,
                  overflowSpacing: KPopSpace.xxs,
                  spacing: KPopSpace.md,
                  children: [
                    Text(l10n.cartItems(cart.itemCount)),
                    Text(
                      Money.crc(cart.estimatedTotal),
                      style: const TextStyle(
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class CartTotal extends StatelessWidget {
  const CartTotal({super.key, required this.amount, required this.amountKey});
  final int amount;
  final Key amountKey;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return OverflowBar(
      alignment: MainAxisAlignment.spaceBetween,
      overflowAlignment: OverflowBarAlignment.start,
      overflowSpacing: KPopSpace.xs,
      spacing: KPopSpace.md,
      children: [
        Text(AppLocalizations.of(context).total, style: text.titleMedium),
        Text(
          Money.crc(amount),
          key: amountKey,
          style: text.titleLarge?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
