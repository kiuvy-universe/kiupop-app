import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiupop/core/theme/app_theme.dart';
import 'package:kiupop/core/theme/theme_controller.dart';
import 'package:kiupop/features/agent/data/agent_models.dart';

void main() {
  test('theme follows the device by default and cycles system→light→dark', () {
    final c = ThemeController();
    expect(c.mode, ThemeMode.system);
    c.cycle();
    expect(c.mode, ThemeMode.light);
    c.cycle();
    expect(c.mode, ThemeMode.dark);
    c.cycle();
    expect(c.mode, ThemeMode.system);
  });

  test('catalog upload is only offered when the backend allows it', () {
    final base = {'field': 'products', 'text': 't', 'reason': 'r'};
    expect(
      KiuQuestion.fromJson({...base, 'allow_upload': true}).allowUpload,
      isTrue,
    );
    expect(KiuQuestion.fromJson(base).allowUpload, isFalse);
  });

  test('chip labels are readable in light and dark', () {
    for (final t in [AppTheme.light(), AppTheme.dark()]) {
      expect(t.chipTheme.labelStyle?.color, t.colorScheme.onSurface);
    }
  });
}
