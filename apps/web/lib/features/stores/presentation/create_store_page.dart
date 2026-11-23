import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app_services.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/kpop_components.dart';
import '../../../l10n/app_localizations.dart';
import '../data/store_models.dart';

/// Step 1: name + WhatsApp (+ optional description). Step 2: show the admin
/// credential once, with a clear warning, before entering the admin.
class CreateStorePage extends StatefulWidget {
  const CreateStorePage({super.key, required this.services});

  final AppServices services;

  @override
  State<CreateStorePage> createState() => _CreateStorePageState();
}

class _CreateStorePageState extends State<CreateStorePage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _whatsapp = TextEditingController();
  final _description = TextEditingController();
  Map<String, String> _serverErrors = const {};
  String? _error;
  bool _saving = false;
  CreatedStore? _created;

  @override
  void dispose() {
    _name.dispose();
    _whatsapp.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _serverErrors = const {};
      _error = null;
    });
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final res = await widget.services.stores.create(
      name: _name.text.trim(),
      whatsapp: _whatsapp.text.trim(),
      description: _description.text.trim(),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    switch (res) {
      case ApiSuccess(:final value):
        widget.services.session.signIn(
          token: value.adminToken,
          store: value.store,
          aiEnabled: value.aiEnabled,
        );
        setState(() => _created = value);
      case ApiFailure() when res.fields.isNotEmpty:
        setState(() => _serverErrors = res.fields);
        _form.currentState!.validate();
      case final ApiFailure<CreatedStore> f:
        setState(() => _error = failureMessage(context, f));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: _created == null
            ? IconButton(
                tooltip: l10n.back,
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.go('/'),
              )
            : null,
        automaticallyImplyLeading: false,
        title: Text(
          _created == null ? l10n.createStoreTitle : l10n.storeReadyTitle,
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: PageBody(
            maxWidth: 560,
            child: _created == null
                ? _buildForm(context)
                : _CredentialStep(
                    created: _created!,
                    services: widget.services,
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Text(
            l10n.createStoreIntro,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _name,
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.words,
            maxLength: 80,
            decoration: InputDecoration(
              labelText: l10n.storeNameLabel,
              hintText: l10n.storeNameHint,
              prefixIcon: const Icon(Icons.storefront_outlined),
            ),
            validator: (v) {
              if (_serverErrors['name'] != null) return _serverErrors['name'];
              return (v == null || v.trim().length < 2)
                  ? l10n.storeNameError
                  : null;
            },
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _whatsapp,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: l10n.whatsappLabel,
              hintText: '8888 8888',
              helperText: l10n.whatsappHelper,
              prefixIcon: const Icon(Icons.chat_outlined),
            ),
            validator: (v) {
              if (_serverErrors['whatsapp'] != null) {
                return _serverErrors['whatsapp'];
              }
              final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
              return digits.length < 8 ? l10n.whatsappError : null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _description,
            maxLines: 3,
            maxLength: 500,
            decoration: InputDecoration(
              labelText: l10n.storeDescriptionLabel,
              hintText: l10n.storeDescriptionHint,
              alignLabelWithHint: true,
            ),
            validator: (_) => _serverErrors['description'],
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _submit,
            child: _saving
                ? const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : Text(l10n.createStoreSubmit),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _CredentialStep extends StatefulWidget {
  const _CredentialStep({required this.created, required this.services});

  final CreatedStore created;
  final AppServices services;

  @override
  State<_CredentialStep> createState() => _CredentialStepState();
}

class _CredentialStepState extends State<_CredentialStep> {
  bool _saved = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final link = widget.services.storeLink(widget.created.store.slug);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Text(
          l10n.storeReadyBody(widget.created.store.name),
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 8),
        SelectableText(
          link.toString(),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.secondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 24),
        KPopSurface(
          flat: true,
          color: KPopTint.butter.background(scheme),
          padding: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.key_rounded,
                      color: KPopTint.butter.foreground(scheme),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.credentialTitle,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: KPopTint.butter.foreground(scheme),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.credentialWarning,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: KPopTint.butter.foreground(scheme),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SelectableText(
                    widget.created.adminToken,
                    key: const Key('admin-token'),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    await widget.services.platform.copyText(
                      widget.created.adminToken,
                    );
                    if (context.mounted) {
                      showSnack(context, l10n.credentialCopied);
                    }
                  },
                  icon: const Icon(Icons.copy_rounded),
                  label: Text(l10n.copyCredential),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        CheckboxListTile(
          value: _saved,
          onChanged: (v) => setState(() => _saved = v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.credentialSavedCheck),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _saved ? () => context.go('/admin') : null,
          child: Text(l10n.continueToProducts),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
