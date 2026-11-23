import 'package:flutter/material.dart';

/// Light / dark / system choice. Defaults to the device setting so people who
/// need dark mode (or high brightness) get it without touching anything.
class ThemeController extends ChangeNotifier {
  ThemeController([this._mode = ThemeMode.system]);

  ThemeMode _mode;
  ThemeMode get mode => _mode;

  set mode(ThemeMode value) {
    if (value == _mode) return;
    _mode = value;
    notifyListeners();
  }

  /// system → light → dark → system.
  void cycle() => mode = switch (_mode) {
    ThemeMode.system => ThemeMode.light,
    ThemeMode.light => ThemeMode.dark,
    ThemeMode.dark => ThemeMode.system,
  };
}
