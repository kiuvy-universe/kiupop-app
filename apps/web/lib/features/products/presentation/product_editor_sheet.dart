import 'package:flutter/material.dart';

import '../../../app_services.dart';
import '../../../core/format/money.dart';
import '../../../core/network/api_client.dart';
import '../../../core/platform/platform_actions.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/kpop_components.dart';
import '../../../l10n/app_localizations.dart';
import '../data/product_models.dart';

/// Opens the create/edit form. Returns the saved product, or null if closed.
Future<AdminProduct?> showProductEditor(
  BuildContext context,
  AppServices services,
  AdminProduct? product,
) {
  return KPopSheet.show<AdminProduct>(
    context: context,
    builder: (_) => ProductEditor(services: services, product: product),
  );
}

class ProductEditor extends StatefulWidget {
  const ProductEditor({super.key, required this.services, this.product});

  final AppServices services;
  final AdminProduct? product;

  @override
  State<ProductEditor> createState() => _ProductEditorState();
}

class _ProductEditorState extends State<ProductEditor> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.product?.name ?? '');
  late final _price = TextEditingController(
    text: widget.product == null
        ? ''
        : Money.editable(widget.product!.priceMinor),
  );
  late final _description = TextEditingController(
    text: widget.product?.description ?? '',
  );
  final _note = TextEditingController();

  PickedImage? _photo;
  AiSuggestion? _suggestion;
  String? _aiError;
  bool _aiLoading = false;
  bool _saving = false;
  String? _error;
  Map<String, String> _serverErrors = const {};

  bool get _isNew => widget.product == null;

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _description.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picked = await widget.services.platform.pickImage();
    if (picked != null && mounted) setState(() => _photo = picked);
  }

  Future<void> _improveWithAi() async {
    final l10n = AppLocalizations.of(context);
    final note = _note.text.trim().isNotEmpty
        ? _note.text.trim()
        : [
            _name.text.trim(),
            _description.text.trim(),
          ].where((s) => s.isNotEmpty).join('. ');
    if (note.length < 3) {
      setState(() => _aiError = l10n.aiNeedsText);
      return;
    }
    setState(() {
      _aiLoading = true;
      _aiError = null;
      _suggestion = null;
    });
    final res = await widget.services.products.suggest(
      widget.services.session.token!,
      note,
    );
    if (!mounted) return;
    setState(() {
      _aiLoading = false;
      switch (res) {
        case ApiSuccess(:final value):
          _suggestion = value;
        case final ApiFailure<AiSuggestion> f:
          _aiError = failureMessage(context, f);
      }
    });
  }

  void _acceptSuggestion() {
    final s = _suggestion!;
    setState(() {
      _name.text = s.name;
      _description.text = s.description;
      _suggestion = null;
    });
    showSnack(context, AppLocalizations.of(context).aiAccepted);
  }

  Future<void> _save() async {
    setState(() {
      _serverErrors = const {};
      _error = null;
    });
    if (!_form.currentState!.validate()) return;
    final token = widget.services.session.token!;
    final api = widget.services.products;
    final price = Money.parseColones(_price.text)!;
    setState(() => _saving = true);

    final ApiResult<AdminProduct> res = _isNew
        ? await api.create(
            token,
            name: _name.text.trim(),
            description: _description.text.trim(),
            priceMinor: price,
          )
        : await api.update(
            token,
            widget.product!.id,
            name: _name.text.trim(),
            description: _description.text.trim(),
            priceMinor: price,
          );

    if (!mounted) return;
    switch (res) {
      case ApiSuccess(:final value):
        var saved = value;
        if (_photo != null) {
          final up = await api.uploadImage(
            token,
            saved.id,
            _photo!.bytes,
            _photo!.filename,
          );
          if (!mounted) return;
          switch (up) {
            case ApiSuccess(:final value):
              saved = value;
            case final ApiFailure<AdminProduct> f:
              // Product is saved; tell the merchant the photo failed and keep the sheet open.
              setState(() {
                _saving = false;
                _error = AppLocalizations.of(context)
                    .photoUploadFailed(failureMessage(context, f));
              });
              return;
          }
        }
        Navigator.of(context).pop(saved);
        showSnack(context, AppLocalizations.of(context).productSaved);
      case ApiFailure() when res.fields.isNotEmpty:
        setState(() {
          _saving = false;
          _serverErrors = res.fields;
        });
        _form.currentState!.validate();
      case final ApiFailure<AdminProduct> f:
        setState(() {
          _saving = false;
          _error = failureMessage(context, f);
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final existingImage = widget.services.products.imageUri(
      widget.product?.imageUrl,
    );
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: PageBody(
          maxWidth: 560,
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _isNew ? l10n.newProductTitle : l10n.editProductTitle,
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
                const SizedBox(height: 12),
                _AiCard(
                  enabled: widget.services.session.aiEnabled,
                  note: _note,
                  loading: _aiLoading,
                  error: _aiError,
                  suggestion: _suggestion,
                  onImprove: _improveWithAi,
                  onAccept: _acceptSuggestion,
                  onDiscard: () => setState(() => _suggestion = null),
                ),
                const SizedBox(height: 16),
                _PhotoPicker(
                  photo: _photo,
                  existing: existingImage,
                  onPick: _pickPhoto,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _name,
                  maxLength: 80,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(labelText: l10n.productNameLabel),
                  validator: (v) =>
                      _serverErrors['name'] ??
                      ((v == null || v.trim().isEmpty)
                          ? l10n.productNameError
                          : null),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _price,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: l10n.priceLabel,
                    prefixText: '₡ ',
                    helperText: l10n.priceHelper,
                  ),
                  validator: (v) =>
                      _serverErrors['price_minor'] ??
                      (Money.parseColones(v ?? '') == null
                          ? l10n.priceError
                          : null),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _description,
                  maxLines: 4,
                  maxLength: 600,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: l10n.productDescriptionLabel,
                    alignLabelWithHint: true,
                  ),
                  validator: (_) => _serverErrors['description'],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : Text(l10n.saveProduct),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AiCard extends StatelessWidget {
  const _AiCard({
    required this.enabled,
    required this.note,
    required this.loading,
    required this.error,
    required this.suggestion,
    required this.onImprove,
    required this.onAccept,
    required this.onDiscard,
  });

  final bool enabled;
  final TextEditingController note;
  final bool loading;
  final String? error;
  final AiSuggestion? suggestion;
  final VoidCallback onImprove;
  final VoidCallback onAccept;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      color: scheme.secondaryContainer.withValues(alpha: 0.6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome, color: AppTheme.seed),
                const SizedBox(width: 8),
                Text('KiuPop AI', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              enabled ? l10n.aiIntro : l10n.aiDisabled,
              style: theme.textTheme.bodySmall,
            ),
            if (enabled) ...[
              const SizedBox(height: 10),
              TextField(
                controller: note,
                maxLines: 2,
                maxLength: 500,
                decoration: InputDecoration(
                  hintText: l10n.aiNoteHint,
                  fillColor: scheme.surface,
                ),
              ),
              OutlinedButton.icon(
                onPressed: loading ? null : onImprove,
                icon: loading
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome),
                label: Text(loading ? l10n.aiWorking : l10n.improveWithAi),
              ),
            ],
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(error!, style: TextStyle(color: scheme.error)),
            ],
            if (suggestion != null) ...[
              const SizedBox(height: 12),
              Container(
                key: const Key('ai-suggestion'),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.aiProposal, style: theme.textTheme.labelMedium),
                    const SizedBox(height: 6),
                    Text(suggestion!.name, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 4),
                    Text(suggestion!.description),
                    const SizedBox(height: 6),
                    Text(
                      l10n.aiPriceUntouched,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonal(
                          onPressed: onAccept,
                          child: Text(l10n.aiUse),
                        ),
                        TextButton(
                          onPressed: onDiscard,
                          child: Text(l10n.aiDiscard),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PhotoPicker extends StatelessWidget {
  const _PhotoPicker({
    required this.photo,
    required this.existing,
    required this.onPick,
  });

  final PickedImage? photo;
  final Uri? existing;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final Widget preview = photo != null
        ? ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.memory(photo!.bytes, fit: BoxFit.cover),
          )
        : ProductImage(url: existing, borderRadius: 14);
    return Row(
      children: [
        SizedBox.square(dimension: 88, child: preview),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              OutlinedButton.icon(
                onPressed: onPick,
                icon: const Icon(Icons.photo_camera_outlined),
                label: Text(
                  photo == null && existing == null
                      ? l10n.addPhoto
                      : l10n.changePhoto,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.photoHelper,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
