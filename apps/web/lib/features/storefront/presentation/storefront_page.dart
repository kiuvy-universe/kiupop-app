import 'dart:math';

import 'package:flutter/material.dart';

import '../../../app_services.dart';
import '../../../core/network/api_client.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/kpop_components.dart';
import '../../../l10n/app_localizations.dart';
import '../../catalog/data/cart.dart';
import '../../catalog/presentation/catalog_page.dart' show CartSheet;
import '../../catalog/presentation/catalog_layout.dart';
import '../data/storefront_api.dart';
import '../data/storefront_models.dart';
import 'storefront_renderer.dart';
import 'storefront_theme.dart';

/// Public store (no login): the published template, cart, WhatsApp order and,
/// when enabled, the test-mode checkout.
class StorefrontPage extends StatefulWidget {
  const StorefrontPage({super.key, required this.services, required this.slug});
  final AppServices services;
  final String slug;

  @override
  State<StorefrontPage> createState() => _StorefrontPageState();
}

class _StorefrontPageState extends State<StorefrontPage> {
  final _cart = Cart();
  StorefrontView? _view;
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
    final res = await widget.services.storefront.load(widget.slug);
    if (!mounted) return;
    setState(() {
      switch (res) {
        case ApiSuccess(:final value):
          _view = value;
          _cart.retainOnly({for (final p in value.products) p.id});
        case final ApiFailure<StorefrontView> f:
          _failure = f;
      }
    });
  }

  void _openCart() {
    final view = _view!;
    KPopSheet.show<void>(
      context: context,
      backgroundColor: view.theme.surface,
      builder: (sheetContext) => Theme(
        data: storefrontTheme(view.theme),
        child: CartSheet(
          services: widget.services,
          slug: widget.slug,
          cart: _cart,
          onStale: _load,
          onTestCheckout: view.payments.testCheckout
              ? () {
                  Navigator.of(sheetContext).pop();
                  _openCheckout(view);
                }
              : null,
        ),
      ),
    );
  }

  void _openCheckout(StorefrontView view) {
    KPopSheet.show<void>(
      context: context,
      backgroundColor: view.theme.surface,
      builder: (_) => Theme(
        data: storefrontTheme(view.theme),
        child: TestCheckoutSheet(
          api: widget.services.storefront,
          slug: widget.slug,
          cart: _cart,
        ),
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
    final view = _view;
    if (view == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Theme(
      data: storefrontTheme(view.theme),
      child: Scaffold(
        backgroundColor: view.theme.background,
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: _load,
            child: StorefrontRenderer(
              view: view,
              imageUri: widget.services.storefront.imageUri,
              cart: _cart,
              onContact: view.contact.whatsappUrl.isEmpty
                  ? null
                  : () => widget.services.platform.openUrl(
                      Uri.parse(view.contact.whatsappUrl),
                    ),
            ),
          ),
        ),
        bottomNavigationBar: CartSummaryButton(cart: _cart, onOpen: _openCart),
      ),
    );
  }
}

/// Test-mode checkout: the server prices the cart and the MockPaymentGateway
/// can only produce *test* outcomes. Labelled everywhere as "prueba".
class TestCheckoutSheet extends StatefulWidget {
  const TestCheckoutSheet({
    super.key,
    required this.api,
    required this.slug,
    required this.cart,
  });
  final StorefrontApi api;
  final String slug;
  final Cart cart;

  @override
  State<TestCheckoutSheet> createState() => _TestCheckoutSheetState();
}

class _TestCheckoutSheetState extends State<TestCheckoutSheet> {
  final _key =
      'chk-${List.generate(12, (_) => Random.secure().nextInt(16).toRadixString(16)).join()}';
  TestPayment? _payment;
  String? _error;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _create();
  }

  Future<void> _create() async {
    final res = await widget.api.checkout(
      widget.slug,
      widget.cart.quantities,
      _key,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = null;
      switch (res) {
        case ApiSuccess(:final value):
          _payment = value;
        case final ApiFailure<TestPayment> f:
          _error = failureMessage(context, f);
      }
    });
  }

  Future<void> _simulate(String outcome) async {
    setState(() => _busy = true);
    final res = await widget.api.simulate(_payment!.id, outcome);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = null;
      switch (res) {
        case ApiSuccess(:final value):
          _payment = value;
          if (value.approved) widget.cart.clear();
        case final ApiFailure<TestPayment> f:
          _error = failureMessage(context, f);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final p = _payment;
    return SingleChildScrollView(
      child: PageBody(
        maxWidth: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.checkoutTitle,
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
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(Icons.science_outlined),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      p?.notice.isNotEmpty == true
                          ? p!.notice
                          : l10n.checkoutTestNotice,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_busy)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              ),
            if (_error != null)
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            if (p == null && _error != null && !_busy)
              TextButton(
                onPressed: () {
                  setState(() {
                    _busy = true;
                    _error = null;
                  });
                  _create();
                },
                child: Text(l10n.retry),
              ),
            if (p != null && !_busy) ...[
              CartTotal(
                amount: p.amountMinor,
                amountKey: const Key('checkout-total'),
              ),
              const SizedBox(height: 16),
              if (p.status == 'pending') ...[
                FilledButton.icon(
                  key: const Key('simulate-approve'),
                  onPressed: () => _simulate('approved'),
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(l10n.checkoutSimulateApprove),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => _simulate('declined'),
                  child: Text(l10n.checkoutSimulateDecline),
                ),
              ] else
                MessageState(
                  icon: p.approved
                      ? Icons.verified_rounded
                      : Icons.block_rounded,
                  title: p.approved
                      ? l10n.checkoutApproved
                      : l10n.checkoutDeclined,
                  body: l10n.checkoutNoRealMoney,
                ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
