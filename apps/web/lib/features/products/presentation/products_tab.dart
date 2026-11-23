import 'package:flutter/material.dart';

import '../../../app_services.dart';
import '../../../core/format/money.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/kpop_components.dart';
import '../../../l10n/app_localizations.dart';
import '../data/product_models.dart';

class ProductsTab extends StatelessWidget {
  const ProductsTab({
    super.key,
    required this.services,
    required this.products,
    required this.failure,
    required this.onRetry,
    required this.onEdit,
    required this.onChanged,
  });

  final AppServices services;
  final List<AdminProduct>? products;
  final ApiFailure<Object?>? failure;
  final VoidCallback onRetry;
  final void Function(AdminProduct) onEdit;
  final void Function(AdminProduct) onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (failure != null) {
      return MessageState(
        icon: Icons.cloud_off_rounded,
        title: l10n.loadProductsError,
        body: failureMessage(context, failure!),
        actionLabel: l10n.retry,
        onAction: onRetry,
      );
    }
    final items = products;
    if (items == null) return const Center(child: CircularProgressIndicator());
    if (items.isEmpty) {
      return MessageState(
        icon: Icons.add_photo_alternate_outlined,
        title: l10n.noProductsTitle,
        body: l10n.noProductsBody,
      );
    }
    return PageBody(
      child: ListView.separated(
        padding: const EdgeInsets.only(top: 12, bottom: 96),
        itemCount: items.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          if (i == 0) {
            return Text(
              l10n.productsCount(items.length),
              style: Theme.of(context).textTheme.titleMedium,
            );
          }
          return _ProductTile(
            key: ValueKey(items[i - 1].id),
            product: items[i - 1],
            services: services,
            onTap: () => onEdit(items[i - 1]),
            onChanged: onChanged,
          );
        },
      ),
    );
  }
}

class _ProductTile extends StatefulWidget {
  const _ProductTile({
    super.key,
    required this.product,
    required this.services,
    required this.onTap,
    required this.onChanged,
  });

  final AdminProduct product;
  final AppServices services;
  final VoidCallback onTap;
  final void Function(AdminProduct) onChanged;

  @override
  State<_ProductTile> createState() => _ProductTileState();
}

class _ProductTileState extends State<_ProductTile> {
  bool _busy = false;

  Future<void> _toggle(bool value) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    final res = await widget.services.products.update(
      widget.services.session.token!,
      widget.product.id,
      available: value,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    switch (res) {
      case ApiSuccess(:final value):
        widget.onChanged(value);
        showSnack(
          context,
          value.available ? l10n.productShown : l10n.productHidden,
        );
      case final ApiFailure<AdminProduct> f:
        showSnack(context, failureMessage(context, f), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = widget.product;
    final theme = Theme.of(context);
    return KPopSurface(
      radius: KPopRadius.tile,
      padding: EdgeInsets.zero,
      onTap: widget.onTap,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 64,
              child: ProductImage(
                url: widget.services.products.imageUri(p.imageUrl),
                borderRadius: KPopRadius.control - 4,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.name, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    Money.crc(p.priceMinor),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.secondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    p.available ? l10n.visibleInStore : l10n.hiddenFromStore,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Semantics(
              label: l10n.availableToggle(p.name),
              child: Switch(
                value: p.available,
                onChanged: _busy ? null : _toggle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
