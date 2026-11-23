import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app_services.dart';
import '../../../core/network/api_client.dart';
import '../../../core/widgets/common.dart';
import '../../../l10n/app_localizations.dart';

/// Lets a signed-in owner open the existing admin (photos, edits) with the same
/// login: the server resolves the store from the verified ID token.
class OwnerAdminBridge extends StatefulWidget {
  const OwnerAdminBridge({super.key, required this.services});
  final AppServices services;
  @override
  State<OwnerAdminBridge> createState() => _OwnerAdminBridgeState();
}

class _OwnerAdminBridgeState extends State<OwnerAdminBridge> {
  ApiFailure<Object?>? _failure;

  @override
  void initState() {
    super.initState();
    _go();
  }

  Future<void> _go() async {
    setState(() => _failure = null);
    final token = await widget.services.auth.idToken();
    if (!mounted) return;
    if (token == null) {
      context.go('/entrar');
      return;
    }
    final res = await widget.services.stores.current(token);
    if (!mounted) return;
    switch (res) {
      case ApiSuccess(:final value):
        widget.services.session.signIn(
          token: token,
          store: value.store,
          aiEnabled: value.aiEnabled,
        );
        context.go('/admin');
      case final ApiFailure<Object?> f:
        setState(() => _failure = f);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final f = _failure;
    return Scaffold(
      body: SafeArea(
        child: f == null
            ? const Center(child: CircularProgressIndicator())
            : MessageState(
                icon: Icons.storefront_outlined,
                title: f.statusCode == 404
                    ? l10n.noStoreYet
                    : l10n.loadCatalogError,
                body: f.statusCode == 404
                    ? l10n.noStoreYetBody
                    : failureMessage(context, f),
                actionLabel: f.statusCode == 404
                    ? l10n.createWithKiu
                    : l10n.retry,
                onAction: f.statusCode == 404 ? () => context.go('/kiu') : _go,
              ),
      ),
    );
  }
}
