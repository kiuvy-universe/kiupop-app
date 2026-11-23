import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app_services.dart';
import '../../../core/network/api_client.dart';
import '../../../core/widgets/common.dart';
import '../../../l10n/app_localizations.dart';

/// Re-enter the admin with the credential saved at creation time.
class AdminLoginPage extends StatefulWidget {
  const AdminLoginPage({super.key, required this.services});

  final AppServices services;

  @override
  State<AdminLoginPage> createState() => _AdminLoginPageState();
}

class _AdminLoginPageState extends State<AdminLoginPage> {
  final _token = TextEditingController();
  String? _error;
  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final token = _token.text.trim();
    if (!token.startsWith('kp_')) {
      setState(() => _error = l10n.credentialInvalid);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await widget.services.stores.current(token);
    if (!mounted) return;
    setState(() => _loading = false);
    switch (res) {
      case ApiSuccess(:final value):
        widget.services.session.signIn(
          token: token,
          store: value.store,
          aiEnabled: value.aiEnabled,
        );
        context.go('/admin');
      case ApiFailure(statusCode: 401):
        setState(() => _error = l10n.credentialInvalid);
      case final ApiFailure<Object?> f:
        setState(() => _error = failureMessage(context, f));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: l10n.back,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
        title: Text(l10n.loginTitle),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: PageBody(
            maxWidth: 560,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                Text(
                  l10n.loginIntro,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _token,
                  obscureText: _obscure,
                  autocorrect: false,
                  enableSuggestions: false,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: l10n.credentialLabel,
                    hintText: 'kp_…',
                    errorText: _error,
                    prefixIcon: const Icon(Icons.key_rounded),
                    suffixIcon: IconButton(
                      tooltip: _obscure ? l10n.show : l10n.hide,
                      icon: Icon(
                        _obscure ? Icons.visibility : Icons.visibility_off,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : Text(l10n.loginSubmit),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.loginRecoveryNote,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
