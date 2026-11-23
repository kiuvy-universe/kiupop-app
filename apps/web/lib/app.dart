import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import 'app_services.dart';
import 'core/theme/app_theme.dart';
import 'l10n/app_localizations.dart';
import 'router.dart';

/// Root widget. Dependencies are passed in (simple constructor injection).
class KiuPopApp extends StatefulWidget {
  const KiuPopApp({
    super.key,
    required this.services,
    this.initialLocation = '/',
  });

  final AppServices services;
  final String initialLocation;

  @override
  State<KiuPopApp> createState() => _KiuPopAppState();
}

class _KiuPopAppState extends State<KiuPopApp> {
  late final GoRouter _router = buildRouter(
    widget.services,
    initialLocation: widget.initialLocation,
  );

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.services.theme,
      builder: (context, _) => _app(context),
    );
  }

  Widget _app(BuildContext context) {
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: widget.services.theme.mode,
      locale: const Locale('es'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: _router,
    );
  }
}
