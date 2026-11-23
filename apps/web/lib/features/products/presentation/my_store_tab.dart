import 'package:flutter/material.dart';

import '../../../app_services.dart';
import '../../../core/format/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/kpop_components.dart';
import '../../../l10n/app_localizations.dart';
import '../data/product_models.dart';

class MyStoreTab extends StatelessWidget {
  const MyStoreTab({super.key, required this.services, required this.products});

  final AppServices services;
  final List<AdminProduct> products;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final store = services.session.store!;
    final link = services.storeLink(store.slug);
    final visible = products.where((p) => p.available).toList();
    return SingleChildScrollView(
      child: PageBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            Text(
              store.name,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (store.description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(store.description, style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: 16),
            KPopSurface(
              color: KPopTint.lavender.background(theme.colorScheme),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l10n.yourLink, style: theme.textTheme.labelLarge),
                  const SizedBox(height: 4),
                  SelectableText(
                    link.toString(),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.secondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => services.platform.openUrl(link),
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: Text(l10n.viewMyStore),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await services.platform.copyText(link.toString());
                      if (context.mounted) {
                        showSnack(context, l10n.linkCopied);
                      }
                    },
                    icon: const Icon(Icons.copy_rounded),
                    label: Text(l10n.copyLink),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.whatsapp,
                      foregroundColor: AppTheme.paper,
                    ),
                    onPressed: () => services.platform.openUrl(
                      Uri.https('wa.me', '/', {
                        'text': l10n.shareMessage(store.name, link.toString()),
                      }),
                    ),
                    icon: const Icon(Icons.chat_rounded),
                    label: Text(l10n.shareWhatsApp),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(l10n.catalogPreview, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            if (visible.isEmpty)
              Text(l10n.catalogPreviewEmpty, style: theme.textTheme.bodyMedium)
            else
              for (final p in visible.take(3))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: SizedBox.square(
                    dimension: 48,
                    child: ProductImage(
                      url: services.products.imageUri(p.imageUrl),
                      borderRadius: 12,
                    ),
                  ),
                  title: Text(p.name),
                  subtitle: Text(Money.crc(p.priceMinor)),
                ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
