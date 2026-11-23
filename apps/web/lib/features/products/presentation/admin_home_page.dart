import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app_services.dart';
import '../../../core/network/api_client.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/settings_sheet.dart';
import '../../../l10n/app_localizations.dart';
import '../data/product_models.dart';
import 'my_store_tab.dart';
import 'product_editor_sheet.dart';
import 'products_tab.dart';

/// Merchant admin: "Productos" and "Mi tienda". Requires an in-memory session
/// (the router redirects to /entrar otherwise).
class AdminHomePage extends StatefulWidget {
  const AdminHomePage({super.key, required this.services});

  final AppServices services;

  @override
  State<AdminHomePage> createState() => _AdminHomePageState();
}

class _AdminHomePageState extends State<AdminHomePage> {
  int _tab = 0;
  List<AdminProduct>? _products;
  ApiFailure<Object?>? _failure;

  String get _token => widget.services.session.token!;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _failure = null);
    final res = await widget.services.products.list(_token);
    if (!mounted) return;
    setState(() {
      switch (res) {
        case ApiSuccess(:final value):
          _products = value;
        case final ApiFailure<List<AdminProduct>> f:
          _failure = f;
      }
    });
  }

  Future<void> _openEditor([AdminProduct? product]) async {
    final saved = await showProductEditor(context, widget.services, product);
    if (saved != null) await _load();
  }

  void _replace(AdminProduct p) {
    setState(() {
      _products = [
        for (final x in _products ?? <AdminProduct>[]) x.id == p.id ? p : x,
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final store = widget.services.session.store!;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            const KiuPopLogo(size: 32, showName: false),
            const SizedBox(width: 12),
            Expanded(child: Text(store.name, overflow: TextOverflow.ellipsis)),
          ],
        ),
        actions: [
          KPopSettingsButton(
            theme: widget.services.theme,
            onSignOut: () async {
              widget.services.session.signOut();
              if (mounted) this.context.go('/');
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: IndexedStack(
          index: _tab,
          children: [
            ProductsTab(
              services: widget.services,
              products: _products,
              failure: _failure,
              onRetry: _load,
              onEdit: _openEditor,
              onChanged: _replace,
            ),
            MyStoreTab(
              services: widget.services,
              products: _products ?? const [],
            ),
          ],
        ),
      ),
      floatingActionButton: _tab == 0
          ? FloatingActionButton.extended(
              onPressed: () => _openEditor(),
              icon: const Icon(Icons.add),
              label: Text(l10n.addProduct),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.inventory_2_outlined),
            selectedIcon: const Icon(Icons.inventory_2),
            label: l10n.tabProducts,
          ),
          NavigationDestination(
            icon: const Icon(Icons.storefront_outlined),
            selectedIcon: const Icon(Icons.storefront),
            label: l10n.tabMyStore,
          ),
        ],
      ),
    );
  }
}
