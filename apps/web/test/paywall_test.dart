import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiupop/core/network/api_client.dart';
import 'package:kiupop/core/theme/app_theme.dart';
import 'package:kiupop/features/agent/data/agent_models.dart';
import 'package:kiupop/features/agent/presentation/paywall_sheet.dart';
import 'package:kiupop/l10n/app_localizations.dart';

import 'helpers.dart';

Widget _host(ThemeData theme, void Function(BuildContext) onTap) => MaterialApp(
  theme: theme,
  locale: const Locale('es'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(
    body: Builder(
      builder: (ctx) =>
          TextButton(onPressed: () => onTap(ctx), child: const Text('abrir')),
    ),
  ),
);

void main() {
  test('paywall parses from the contract and needs a plan before publish', () {
    final s = AgentSession.fromJson(contractExample('agent_session.json'));
    expect(s.paywall.required, isTrue);
    expect(s.paywall.active, isFalse);
    expect(s.paywall.priceLabel, 'US\$5');
    expect(s.paywall.isTest, isTrue);
    expect(s.needsPlan, isTrue);
    final active = PaywallInfo.fromJson(
      contractExample('agent_plan_response.json'),
    );
    expect(active.active, isTrue);
    // Older servers without the field: no paywall, free publish as before.
    final legacy = Map<String, dynamic>.of(
      contractExample('agent_session.json'),
    )..remove('paywall');
    expect(AgentSession.fromJson(legacy).needsPlan, isFalse);
  });

  for (final (name, theme) in [
    ('light', AppTheme.light()),
    ('dark', AppTheme.dark()),
  ]) {
    testWidgets('paywall shows price, test badge and pays ($name)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var calls = 0;
      bool? result;
      await tester.pumpWidget(
        _host(theme, (ctx) async {
          result = await PaywallSheet.show(
            ctx,
            paywall: const PaywallInfo(
              required: true,
              active: false,
              priceMinor: 500,
              currency: 'USD',
              mode: 'test',
              notice: '',
            ),
            pay: () async {
              calls++;
              return ApiSuccess(
                PaywallInfo.fromJson(
                  contractExample('agent_plan_response.json'),
                ),
              );
            },
          );
        }),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('paywall-sheet')), findsOneWidget);
      expect(find.text('Modo demostración'), findsOneWidget);
      expect(
        find.text(
          'Modo demostración. KiuPop todavía no procesa suscripciones ni cobros reales. Esta activación es simulada y no se cargará ningún monto.',
        ),
        findsOneWidget,
      );
      expect(find.text('Pagos en línea reales'), findsOneWidget);
      expect(find.textContaining('4242'), findsNothing);
      expect(find.textContaining('US\$5'), findsWidgets);
      expect(find.text('Simular activación'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byKey(const Key('paywall-pay')));
      await tester.tap(find.byKey(const Key('paywall-pay')));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(result, isTrue);
      expect(find.byKey(const Key('paywall-sheet')), findsNothing);
    });
  }

  testWidgets('a failed test payment keeps the sheet open with the error', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    bool? result;
    await tester.pumpWidget(
      _host(AppTheme.light(), (ctx) async {
        result = await PaywallSheet.show(
          ctx,
          paywall: PaywallInfo.off,
          pay: () async => const ApiFailure(
            ApiFailureKind.server,
            statusCode: 503,
            code: 'payments_unavailable',
            message: 'Los pagos no están disponibles en este entorno.',
          ),
        );
      }),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('paywall-pay')));
    await tester.tap(find.byKey(const Key('paywall-pay')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('paywall-error')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('paywall-later')));
    await tester.tap(find.byKey(const Key('paywall-later')));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });
}
