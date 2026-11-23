import 'package:web/web.dart' as web;

/// Reads the CSS media query `prefers-reduced-motion: reduce`.
bool systemPrefersReducedMotion() =>
    web.window.matchMedia('(prefers-reduced-motion: reduce)').matches;
