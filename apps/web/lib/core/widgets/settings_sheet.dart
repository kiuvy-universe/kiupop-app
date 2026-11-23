import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import 'kpop_components.dart';

/// One quiet entry point for secondary controls (appearance, how Kiu thinks,
/// sign out) so the header keeps a single action.
class KPopSettingsButton extends StatelessWidget {
  const KPopSettingsButton({
    super.key,
    required this.theme,
    this.aiMode,
    this.onSignOut,
  });

  final ThemeController theme;

  /// `claude` or `local`; null hides the row.
  final String? aiMode;
  final Future<void> Function()? onSignOut;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return IconButton(
      key: const Key('open-settings'),
      tooltip: l10n.settingsTitle,
      icon: const Icon(Icons.tune_rounded),
      onPressed: () => KPopSheet.show<void>(
        context: context,
        builder: (_) =>
            _SettingsSheet(theme: theme, aiMode: aiMode, onSignOut: onSignOut),
      ),
    );
  }
}

class _SettingsSheet extends StatelessWidget {
  const _SettingsSheet({required this.theme, this.aiMode, this.onSignOut});

  final ThemeController theme;
  final String? aiMode;
  final Future<void> Function()? onSignOut;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final claude = aiMode == 'claude';
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          KPopSpace.gutter,
          0,
          KPopSpace.gutter,
          KPopSpace.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(l10n.settingsTitle, style: text.titleLarge),
                  ),
                ),
                IconButton(
                  tooltip: l10n.close,
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: KPopSpace.md),
            Text(l10n.themeLabel, style: text.titleSmall),
            const SizedBox(height: KPopSpace.xs),
            // Chips wrap at 360 dp with large text instead of clipping.
            ListenableBuilder(
              listenable: theme,
              builder: (context, _) => Wrap(
                key: const Key('theme-mode'),
                spacing: KPopSpace.xs,
                runSpacing: KPopSpace.xs,
                children: [
                  for (final (mode, icon, label, hint) in [
                    (
                      ThemeMode.system,
                      Icons.brightness_auto_outlined,
                      l10n.themeShortSystem,
                      l10n.themeSystem,
                    ),
                    (
                      ThemeMode.light,
                      Icons.light_mode_outlined,
                      l10n.themeShortLight,
                      l10n.themeLight,
                    ),
                    (
                      ThemeMode.dark,
                      Icons.dark_mode_outlined,
                      l10n.themeShortDark,
                      l10n.themeDark,
                    ),
                  ])
                    Tooltip(
                      message: hint,
                      child: ChoiceChip(
                        avatar: Icon(icon, size: 18),
                        label: Text(label),
                        selected: theme.mode == mode,
                        showCheckmark: false,
                        onSelected: (_) => theme.mode = mode,
                      ),
                    ),
                ],
              ),
            ),
            if (aiMode != null) ...[
              const SizedBox(height: KPopSpace.lg),
              Text(l10n.kiuBrainLabel, style: text.titleSmall),
              const SizedBox(height: KPopSpace.xs),
              KPopClayTile(
                tint: claude ? KPopTint.lavender : KPopTint.mint,
                icon: claude
                    ? Icons.auto_awesome_outlined
                    : Icons.memory_rounded,
                label: claude ? l10n.aiModeClaude : l10n.aiModeLocal,
                subtitle: claude ? l10n.aiModeClaudeHelp : l10n.aiModeLocalHelp,
              ),
            ],
            if (onSignOut != null) ...[
              const SizedBox(height: KPopSpace.lg),
              KPopButton(
                key: const Key('sign-out'),
                tone: KPopButtonTone.outlined,
                icon: Icons.logout_rounded,
                label: l10n.signOut,
                expand: true,
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final failed = l10n.errorGeneric;
                  Navigator.of(context).pop();
                  try {
                    await onSignOut!();
                  } on Object {
                    messenger.showSnackBar(SnackBar(content: Text(failed)));
                  }
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
