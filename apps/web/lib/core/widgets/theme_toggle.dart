import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../theme/theme_controller.dart';

class ThemeToggle extends StatelessWidget {
  const ThemeToggle({super.key, required this.controller});

  final ThemeController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final l10n = AppLocalizations.of(context);
      final (icon, label) = switch (controller.mode) {
        ThemeMode.system => (Icons.brightness_auto_outlined, l10n.themeSystem),
        ThemeMode.light => (Icons.light_mode_outlined, l10n.themeLight),
        ThemeMode.dark => (Icons.dark_mode_outlined, l10n.themeDark),
      };
      return IconButton(
        key: const Key('theme-toggle'),
        tooltip: label,
        onPressed: controller.cycle,
        icon: Icon(icon),
      );
    },
  );
}
