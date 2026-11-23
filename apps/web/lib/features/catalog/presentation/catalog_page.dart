import 'package:flutter/material.dart';

import '../../../app_services.dart';
import '../../../core/format/money.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/kpop_components.dart';
import '../../../l10n/app_localizations.dart';
import '../../products/data/product_models.dart';
import '../../stores/data/store_models.dart';
import '../data/cart.dart';
import 'catalog_layout.dart';

/// Public catalog: no login, no admin credential, only this store's products.
class CatalogPage extends StatefulWidget {
  const CatalogPage({super.key, required this.services, required this.slug});

  final AppServices services;
  final String slug;

  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  final _cart = Cart();
  PublicStore? _store;
  List<PublicProduct>? _products;
  ApiFailure<Object?>? _failure;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _cart.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _failure = null);
    final api = widget.services.catalog;
    final results = await Future.wait([
      api.store(widget.slug),
      api.products(widget.slug),
    ]);
    if (!mounted) return;
    setState(() {
      switch ((results[0], results[1])) {
        case (
          ApiSuccess(value: final PublicStore s),
          ApiSuccess(value: final List<PublicProduct> p),
        ):
          _store = s;
          _products = p;
          _cart.retainOnly({for (final x in p) x.id});
        case (final ApiFailure<Object?> f, _):
          _failure = f;
        case (_, final ApiFailure<Object?> f):
          _failure = f;
        default:
          _failure = const ApiFailure(ApiFailureKind.badResponse);
      }
    });
  }

  void _openCart() {
    KPopSheet.show<void>(
      context: context,
      builder: (_) => CartSheet(
        services: widget.services,
        slug: widget.slug,
        cart: _cart,
        onStale: _load,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final f = _failure;
    if (f != null) {
      final notFound = f.statusCode == 404;
      return Scaffold(
        body: SafeArea(
          child: MessageState(
            icon: notFound
                ? Icons.storefront_outlined
                : Icons.cloud_off_rounded,
            title: notFound ? l10n.storeNotFound : l10n.loadCatalogError,
            body: notFound
                ? l10n.storeNotFoundBody
                : failureMessage(context, f),
            actionLabel: notFound ? null : l10n.retry,
            onAction: notFound ? null : _load,
          ),
        ),
      );
    }
    final store = _store;
    final products = _products;
    if (store == null || products == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _Header(store: store)),
              if (products.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: MessageState(
                    icon: Icons.local_florist_outlined,
                    title: l10n.catalogEmpty,
                    body: l10n.catalogEmptyBody,
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                  sliver: SliverLayoutBuilder(
                    builder: (context, constraints) {
                      return SliverGrid(
                        gridDelegate: catalogGrid(
                          context,
                          constraints.crossAxisExtent,
                          spacing: KPopSpace.sm,
                          height: 320,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, i) => _ProductCard(
                            product: products[i],
                            imageUrl: widget.services.catalog.imageUri(
                              products[i].imageUrl,
                            ),
                            cart: _cart,
                          ),
                          childCount: products.length,
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: CartSummaryButton(cart: _cart, onOpen: _openCart),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.store});

  final PublicStore store;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        gradient: LinearGradient(
          colors: [scheme.primaryContainer, scheme.tertiaryContainer],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            store.name,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          if (store.description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(store.description, style: theme.textTheme.bodyMedium),
          ],
          const SizedBox(height: 12),
          const Opacity(opacity: 0.8, child: KiuPopLogo(size: 20)),
        ],
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.imageUrl,
    required this.cart,
  });

  final PublicProduct product;
  final Uri? imageUrl;
  final Cart cart;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: 136, child: ProductImage(url: imageUrl)),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Expanded(
                    child: Text(
                      product.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Text(
                    Money.crc(product.priceMinor),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
            child: ListenableBuilder(
              listenable: cart,
              builder: (context, _) {
                final q = cart.quantityOf(product.id);
                if (q == 0) {
                  return FilledButton.tonalIcon(
                    onPressed: () => cart.add(product),
                    icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
                    label: Text(l10n.addToCart),
                  );
                }
                return QuantityStepper(
                  quantity: q,
                  name: product.name,
                  onMinus: () => cart.decrement(product.id),
                  onPlus: () => cart.add(product),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class QuantityStepper extends StatelessWidget {
  const QuantityStepper({
    super.key,
    required this.quantity,
    required this.name,
    required this.onMinus,
    required this.onPlus,
  });

  final int quantity;
  final String name;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: l10n.decrease(name),
            onPressed: onMinus,
            icon: Icon(quantity == 1 ? Icons.delete_outline : Icons.remove),
          ),
          Expanded(
            child: Text(
              '$quantity',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
          ),
          IconButton(
            tooltip: l10n.increase(name),
            onPressed: quantity >= Cart.maxQuantity ? null : onPlus,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}

/// Order review. "Pedir por WhatsApp" asks the server to price the order, then
/// opens wa.me with the prepared message. Nothing is sent or confirmed by us.
class CartSheet extends StatefulWidget {
  const CartSheet({
    super.key,
    required this.services,
    required this.slug,
    required this.cart,
    required this.onStale,
    this.onTestCheckout,
  });

  final AppServices services;
  final String slug;
  final Cart cart;
  final Future<void> Function() onStale;

  /// Shown only when the store has the test-mode checkout (never real money).
  final VoidCallback? onTestCheckout;

  @override
  State<CartSheet> createState() => _CartSheetState();
}

class _CartSheetState extends State<CartSheet> {
  bool _sending = false;
  String? _error;

  Future<void> _order() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    final res = await widget.services.catalog.preview(
      widget.slug,
      widget.cart.quantities,
    );
    if (!mounted) return;
    switch (res) {
      case ApiSuccess(:final value):
        final opened = await widget.services.platform.openUrl(
          value.whatsappUrl,
        );
        if (!mounted) return;
        setState(() => _sending = false);
        if (!opened) {
          setState(
            () => _error = AppLocalizations.of(context).whatsappOpenFailed,
          );
          return;
        }
        Navigator.of(context).pop();
        showSnack(context, AppLocalizations.of(context).orderPrepared);
      case final ApiFailure<Object?> f:
        setState(() {
          _sending = false;
          _error = failureMessage(context, f);
        });
        if (f.code == 'product_unavailable' || f.code == 'product_not_found') {
          await widget.onStale();
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: widget.cart,
      builder: (context, _) {
        final cart = widget.cart;
        return SingleChildScrollView(
          child: PageBody(
            maxWidth: 560,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.yourOrder,
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: l10n.close,
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (cart.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(l10n.cartEmpty, textAlign: TextAlign.center),
                  )
                else ...[
                  for (final p in cart.products)
                    _CartLine(cart: cart, product: p),
                  const Divider(height: KPopSpace.lg),
                  CartTotal(
                    amount: cart.estimatedTotal,
                    amountKey: const Key('cart-total'),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.orderDisclaimer,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    key: const Key('order-whatsapp'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.whatsapp,
                      foregroundColor: AppTheme.paper,
                    ),
                    onPressed: _sending ? null : _order,
                    icon: _sending
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.chat_rounded),
                    label: Text(l10n.orderWhatsApp),
                  ),
                  if (widget.onTestCheckout != null) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      key: const Key('test-checkout'),
                      onPressed: _sending ? null : widget.onTestCheckout,
                      icon: const Icon(Icons.credit_card_rounded),
                      label: Text(l10n.sfTestCheckout),
                    ),
                  ],
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CartLine extends StatelessWidget {
  const _CartLine({required this.cart, required this.product});
  final Cart cart;
  final PublicProduct product;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: KPopSpace.xs),
      child: LayoutBuilder(
        builder: (context, bounds) {
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(product.name, style: text.titleSmall),
              Text(
                '${Money.crc(product.priceMinor)} · ${l10n.subtotal}: ${Money.crc(cart.subtotalOf(product.id))}',
                style: text.bodySmall,
              ),
            ],
          );
          final stepper = SizedBox(
            width: 148,
            child: QuantityStepper(
              quantity: cart.quantityOf(product.id),
              name: product.name,
              onMinus: () => cart.decrement(product.id),
              onPlus: () => cart.add(product),
            ),
          );
          if (bounds.maxWidth < 420 ||
              MediaQuery.textScalerOf(context).scale(16) > 24) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                details,
                const SizedBox(height: KPopSpace.xs),
                stepper,
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: details),
              const SizedBox(width: KPopSpace.md),
              stepper,
            ],
          );
        },
      ),
    );
  }
}
