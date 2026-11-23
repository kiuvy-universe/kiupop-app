import 'package:flutter/material.dart';

import '../../../core/format/money.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/widgets/common.dart';
import '../../catalog/data/cart.dart';
import '../../catalog/presentation/catalog_page.dart' show QuantityStepper;
import '../../catalog/presentation/catalog_layout.dart';
import '../../products/data/product_models.dart';
import '../data/storefront_models.dart';
import 'storefront_theme.dart';

/// Renders any approved template from validated tokens. The AI never produces
/// widgets or CSS: it only picks the template and tokens this renderer reads.
class StorefrontRenderer extends StatelessWidget {
  const StorefrontRenderer({
    super.key,
    required this.view,
    required this.imageUri,
    this.cart,
    this.onContact,
    this.bottomPadding = 120,
    this.shrinkWrap = false,
  });

  final StorefrontView view;
  final Uri? Function(String? path) imageUri;

  /// Null in the owner's preview (ordering is enabled after publication).
  final Cart? cart;
  final VoidCallback? onContact;
  final double bottomPadding;
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    final t = view.theme;
    final gap = t.compact ? 12.0 : 20.0;
    final featured = view.products.where((p) => p.featured).toList();
    final slivers = <Widget>[];
    for (final s in t.sections) {
      switch (s) {
        case 'hero':
          slivers.add(
            SliverToBoxAdapter(
              child: _Hero(
                view: view,
                onContact: onContact,
                gap: gap,
                coverUri: imageUri(view.store.coverUrl),
              ),
            ),
          );
        case 'featured' when featured.length >= 2:
          slivers.add(
            SliverToBoxAdapter(
              child: _Featured(
                products: featured,
                imageUri: imageUri,
                gap: gap,
              ),
            ),
          );
        case 'catalog':
          slivers.addAll(_catalog(context, gap));
        case 'delivery':
          slivers.add(
            SliverToBoxAdapter(
              child: _DeliveryCard(view: view, gap: gap),
            ),
          );
        case 'contact':
          slivers.add(
            SliverToBoxAdapter(
              child: _ContactCard(view: view, onContact: onContact, gap: gap),
            ),
          );
      }
    }
    slivers.add(SliverToBoxAdapter(child: _Footer(draft: view.isDraft)));
    slivers.add(SliverToBoxAdapter(child: SizedBox(height: bottomPadding)));
    return Theme(
      data: storefrontTheme(t),
      child: Builder(
        builder: (context) => ColoredBox(
          color: t.background,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1300),
              child: CustomScrollView(
                shrinkWrap: shrinkWrap,
                physics: shrinkWrap
                    ? null
                    : const AlwaysScrollableScrollPhysics(),
                slivers: slivers,
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _catalog(BuildContext context, double gap) {
    final l10n = AppLocalizations.of(context);
    if (view.products.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(gap),
            child: Text(l10n.catalogEmpty, textAlign: TextAlign.center),
          ),
        ),
      ];
    }
    final anyDescription = view.products.any((p) => p.description.isNotEmpty);
    return [
      SliverToBoxAdapter(child: _SectionTitle(l10n.sfCatalog, gap: gap)),
      SliverPadding(
        padding: EdgeInsets.symmetric(horizontal: gap),
        sliver: SliverLayoutBuilder(
          builder: (context, c) {
            return SliverGrid(
              gridDelegate: catalogGrid(
                context,
                c.crossAxisExtent,
                spacing: gap * .7,
                height: (cart == null ? 286 : 330) - (anyDescription ? 0 : 44),
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => _ProductCard(
                  product: view.products[i],
                  imageUri: imageUri,
                  cart: cart,
                ),
                childCount: view.products.length,
              ),
            );
          },
        ),
      ),
    ];
  }
}

PublicProduct toPublic(StoreProduct p) => PublicProduct(
  id: p.id,
  name: p.name,
  description: p.description,
  priceMinor: p.priceMinor,
  currency: 'CRC',
  imageUrl: p.imageUrl,
);

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {required this.gap});
  final String text;
  final double gap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(gap, gap * 1.4, gap, gap * 0.6),
    child: Text(text, style: Theme.of(context).textTheme.headlineSmall),
  );
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.view,
    required this.onContact,
    required this.gap,
    this.coverUri,
  });
  final Uri? coverUri;
  final StorefrontView view;
  final VoidCallback? onContact;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = view.theme;
    final theme = Theme.of(context);
    return Container(
      margin: EdgeInsets.fromLTRB(gap * 0.6, gap * 0.6, gap * 0.6, 0),
      padding: EdgeInsets.fromLTRB(gap * 1.3, gap * 1.8, gap * 1.3, gap * 1.5),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(t.radius * 1.4),
        // The merchant's cover photo, washed with the background so text keeps its contrast.
        image: coverUri == null
            ? null
            : DecorationImage(
                image: NetworkImage(coverUri.toString()),
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(
                  t.background.withValues(alpha: 0.72),
                  BlendMode.srcOver,
                ),
              ),
        color: Color.alphaBlend(
          t.secondary.withValues(alpha: .46),
          t.background,
        ),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            right: -10,
            top: -18,
            child: _Dot(size: 92, color: t.accent.withValues(alpha: 0.35)),
          ),
          Positioned(
            right: 64,
            top: 50,
            child: _Dot(size: 26, color: t.primary.withValues(alpha: 0.25)),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (view.store.category.isNotEmpty)
                Text(
                  _categoryLabel(l10n, view.store.category).toUpperCase(),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: t.primary,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              const SizedBox(height: 8),
              Semantics(
                header: true,
                child: Text(
                  view.store.name,
                  style: theme.textTheme.displaySmall,
                ),
              ),
              if (view.store.tagline.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  view.store.tagline,
                  style: theme.textTheme.titleMedium?.copyWith(color: t.muted),
                ),
              ],
              if (view.store.description.isNotEmpty) ...[
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Text(
                    view.store.description,
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (view.contact.whatsappUrl.isNotEmpty)
                    FilledButton.icon(
                      onPressed: onContact,
                      icon: const Icon(Icons.chat_rounded),
                      label: Text(
                        onContact == null
                            ? l10n.sfAvailableWhenPublished
                            : l10n.sfWriteWhatsApp,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _categoryLabel(AppLocalizations l10n, String c) => switch (c) {
  'flores' => l10n.catFlores,
  'reposteria' => l10n.catReposteria,
  'comida' => l10n.catComida,
  'ropa' => l10n.catRopa,
  'belleza' => l10n.catBelleza,
  'artesania' => l10n.catArtesania,
  'mascotas' => l10n.catMascotas,
  'plantas' => l10n.catPlantas,
  'tecnologia' => l10n.catTecnologia,
  _ => l10n.catOtro,
};

class _Dot extends StatelessWidget {
  const _Dot({required this.size, required this.color});
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    ),
  );
}

class _Featured extends StatelessWidget {
  const _Featured({
    required this.products,
    required this.imageUri,
    required this.gap,
  });
  final List<StoreProduct> products;
  final Uri? Function(String?) imageUri;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(l10n.sfFeatured, gap: gap),
        SizedBox(
          height: 190,
          child: ListView.separated(
            padding: EdgeInsets.symmetric(horizontal: gap),
            scrollDirection: Axis.horizontal,
            itemCount: products.length,
            separatorBuilder: (_, _) => SizedBox(width: gap * 0.7),
            itemBuilder: (context, i) {
              final p = products[i];
              return SizedBox(
                width: 260,
                child: Card(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ProductArt(product: p, url: imageUri(p.imageUrl)),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.55),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 14,
                        right: 14,
                        bottom: 12,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              Money.crc(p.priceMinor),
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Product photo, or a generated pastel tile in the store's palette.
class ProductArt extends StatelessWidget {
  const ProductArt({super.key, required this.product, required this.url});
  final StoreProduct product;
  final Uri? url;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initial = product.name.characters.firstOrNull?.toUpperCase() ?? '';
    final placeholder = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.secondaryContainer,
            scheme.secondary.withValues(alpha: 0.55),
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -12,
            top: -12,
            child: _Dot(size: 64, color: Colors.white.withValues(alpha: 0.35)),
          ),
          Positioned(
            left: 14,
            bottom: 10,
            child: _Dot(size: 18, color: Colors.white.withValues(alpha: 0.5)),
          ),
          Center(
            child: ExcludeSemantics(
              child: Text(
                initial,
                textScaler: TextScaler.noScaling, // Decorative initial.
                style: TextStyle(
                  fontSize: 44,
                  fontWeight: FontWeight.w900,
                  color: scheme.primary.withValues(alpha: 0.85),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    return ProductImage(url: url, placeholder: placeholder);
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.imageUri,
    required this.cart,
  });
  final StoreProduct product;
  final Uri? Function(String?) imageUri;
  final Cart? cart;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cart = this.cart;
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 140,
            child: ProductArt(
              product: product,
              url: imageUri(product.imageUrl),
            ),
          ),
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
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Expanded(
                    child: Text(
                      product.description,
                      maxLines: 3,
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
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (cart != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
              child: ListenableBuilder(
                listenable: cart,
                builder: (context, _) {
                  final q = cart.quantityOf(product.id);
                  if (q == 0) {
                    return FilledButton.tonalIcon(
                      onPressed: () => cart.add(toPublic(product)),
                      icon: const Icon(
                        Icons.add_shopping_cart_rounded,
                        size: 18,
                      ),
                      label: Text(l10n.addToCart),
                    );
                  }
                  return QuantityStepper(
                    quantity: q,
                    name: product.name,
                    onMinus: () => cart.decrement(product.id),
                    onPlus: () => cart.add(toPublic(product)),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _DeliveryCard extends StatelessWidget {
  const _DeliveryCard({required this.view, required this.gap});
  final StorefrontView view;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final d = view.delivery;
    final rows = <Widget>[
      if (d.modes.contains('delivery'))
        _InfoRow(
          icon: Icons.delivery_dining_rounded,
          text: l10n.sfDeliveryHome,
        ),
      if (d.modes.contains('pickup'))
        _InfoRow(icon: Icons.storefront_rounded, text: l10n.sfDeliveryPickup),
      if (d.modes.isEmpty)
        _InfoRow(
          icon: Icons.chat_bubble_outline_rounded,
          text: l10n.sfDeliveryCoordinate,
        ),
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(gap, gap * 1.4, gap, 0),
      child: Card(
        child: Padding(
          padding: EdgeInsets.all(gap),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.sfDelivery, style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              ...rows,
              if (d.zones.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [for (final z in d.zones) Chip(label: Text(z))],
                ),
              ],
              if (view.payments.methodsToCoordinate.isNotEmpty) ...[
                const SizedBox(height: 12),
                _InfoRow(
                  icon: Icons.payments_outlined,
                  text: l10n.sfPaymentsToCoordinate(
                    view.payments.methodsToCoordinate.join(', '),
                  ),
                ),
              ],
              if (!view.payments.realPaymentsEnabled) ...[
                const SizedBox(height: 4),
                _InfoRow(
                  icon: Icons.info_outline_rounded,
                  text: l10n.sfRealPaymentsPending,
                  muted: true,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text, this.muted = false});
  final IconData icon;
  final String text;
  final bool muted;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            icon,
            color: muted ? scheme.onSurfaceVariant : scheme.primary,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: muted ? scheme.onSurfaceVariant : scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({
    required this.view,
    required this.onContact,
    required this.gap,
  });
  final StorefrontView view;
  final VoidCallback? onContact;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(gap, gap * 1.4, gap, 0),
      child: Card(
        child: Padding(
          padding: EdgeInsets.all(gap),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.sfContact, style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              if (view.contact.whatsappUrl.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: onContact,
                  icon: const Icon(Icons.chat_rounded),
                  label: Text(
                    onContact == null
                        ? l10n.sfAvailableWhenPublished
                        : l10n.sfWriteWhatsApp,
                  ),
                ),
              if (view.contact.instagram.isNotEmpty)
                _InfoRow(
                  icon: Icons.camera_alt_outlined,
                  text: '@${view.contact.instagram}',
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.draft});
  final bool draft;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Center(
        child: Text(
          draft ? l10n.sfDraftBadge : l10n.sfMadeWith,
          style: TextStyle(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
