import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiupop/features/agent/data/agent_models.dart';
import 'package:kiupop/features/agent/presentation/kiu_bubble.dart';
import 'package:kiupop/features/storefront/data/storefront_api.dart';
import 'package:kiupop/features/storefront/data/storefront_models.dart';
import 'package:kiupop/features/storefront/presentation/storefront_renderer.dart';
import 'package:kiupop/l10n/app_localizations.dart';

import 'helpers.dart';

Widget _host(Widget child) => MaterialApp(
  locale: const Locale('es'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(body: child),
);

void main() {
  test('Dart models parse the agent, storefront and payment examples', () {
    final s = AgentSession.fromJson(contractExample('agent_session.json'));
    expect(s.ready, isTrue);
    expect(s.percent, 100);
    expect(s.messages.first.fromKiu, isTrue);
    final v = StorefrontView.fromJson(contractExample('storefront_view.json'));
    expect(v.products, isNotEmpty);
    expect(v.payments.realPaymentsEnabled, isFalse);
    expect(v.theme.sections.first, 'hero');
    expect(
      PublishResult.fromJson(contractExample('agent_publish_response.json'))
          .shareUrl,
      contains('/p/'),
    );
    final pay = TestPayment.fromJson(contractExample('payment.json'));
    expect(pay.status, 'pending');
    expect(pay.notice, contains('no se cobra dinero real'));
  });

  for (final template in ['bubblegum_pink', 'mint_fresh', 'peach_pop']) {
    testWidgets('$template renders from tokens on phone and desktop', (
      tester,
    ) async {
      final api = FakeApi()
        ..addProduct('Ramo de rosas', 1500000)
        ..addProduct('Caja de regalo', 1250000);
      final json = api.storefront(status: 'published', template: template);
      final view = StorefrontView.fromJson(json);
      for (final size in [const Size(390, 844), const Size(1366, 860)]) {
        tester.view.physicalSize = size * 2;
        tester.view.devicePixelRatio = 2;
        await tester.pumpWidget(
          _host(
            StorefrontRenderer(
              key: ValueKey(size),
              view: view,
              imageUri: (_) => null,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Flores de Occidente'), findsOneWidget);
        expect(find.text('₡15.000'), findsWidgets);
        await tester.scrollUntilVisible(
          find.text('Pagos en línea reales: pendientes de activar.'),
          300,
        );
      }
      tester.view.reset();
    });
  }

  testWidgets('draft preview disables ordering', (tester) async {
    final api = FakeApi()..addProduct('Ramo de rosas', 1500000);
    final view = StorefrontView.fromJson(api.storefront(status: 'draft'));
    await tester.pumpWidget(
      _host(StorefrontRenderer(view: view, imageUri: (_) => null)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Agregar'), findsNothing);
    await tester.scrollUntilVisible(find.text('Vista previa · borrador'), 300);
  });

  testWidgets('test checkout: server-priced, labelled as test, settles', (
    tester,
  ) async {
    final api = FakeApi()
      ..addProduct('Ramo de rosas', 1500000)
      ..testCheckout = true;
    await pumpApp(
      tester,
      servicesFor(api, FakePlatform()),
      at: '/s/flores-de-occidente',
    );
    await tapVisible(tester, find.text('Agregar').first);
    await tapVisible(tester, find.byKey(const Key('open-cart')));
    await tapVisible(tester, find.byKey(const Key('test-checkout')));
    expect(find.text('₡15.000'), findsWidgets);
    expect(find.textContaining('no se cobra dinero real'), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('simulate-approve')));
    expect(find.text('Pago de prueba aprobado'), findsOneWidget);
    final req = api.requests.firstWhere(
      (r) => r.url.path.endsWith('/checkout'),
    );
    expect(req.body, isNot(contains('price')));
  });

  testWidgets('retrying a test checkout keeps the same idempotency key', (
    tester,
  ) async {
    final api = FakeApi()
      ..addProduct('Ramo de rosas', 1500000)
      ..testCheckout = true
      ..checkoutFailures = 1;
    await pumpApp(
      tester,
      servicesFor(api, FakePlatform()),
      at: '/s/flores-de-occidente',
    );
    await tapVisible(tester, find.text('Agregar').first);
    await tapVisible(tester, find.byKey(const Key('open-cart')));
    await tapVisible(tester, find.byKey(const Key('test-checkout')));
    expect(find.text('El checkout no está disponible.'), findsOneWidget);
    await tapVisible(tester, find.text('Reintentar'));
    expect(find.byKey(const Key('checkout-total')), findsOneWidget);
    final keys = api.requests
        .where((r) => r.url.path.endsWith('/checkout'))
        .map((r) => (jsonDecode(r.body) as Map)['idempotency_key'])
        .toList();
    expect(keys, hasLength(2));
    expect(keys.first, isNotEmpty);
    expect(keys.last, keys.first);
  });

  testWidgets('without test checkout only WhatsApp ordering is offered', (
    tester,
  ) async {
    final api = FakeApi()..addProduct('Ramo de rosas', 1500000);
    await pumpApp(
      tester,
      servicesFor(api, FakePlatform()),
      at: '/s/flores-de-occidente',
    );
    await tapVisible(tester, find.text('Agregar').first);
    await tapVisible(tester, find.byKey(const Key('open-cart')));
    expect(find.byKey(const Key('test-checkout')), findsNothing);
  });

  testWidgets('Kiu bubble POP plays once and reports completion', (
    tester,
  ) async {
    var popped = 0;
    Widget bubble(bool pop, KiuMood mood) => _host(
      KiuBubbleAnimation(
        progress: 1,
        mood: mood,
        pop: pop,
        onPopped: () => popped++,
      ),
    );
    await tester.pumpWidget(bubble(false, KiuMood.processing));
    await tester.pump(const Duration(milliseconds: 300));
    expect(popped, 0, reason: 'no POP without backend readiness');
    await tester.pumpWidget(bubble(true, KiuMood.success));
    await tester.pump(const Duration(milliseconds: 500));
    expect(popped, 0);
    await tester.pump(const Duration(milliseconds: 500));
    expect(popped, 1);
    await tester.pumpWidget(bubble(true, KiuMood.success));
    await tester.pump(const Duration(seconds: 1));
    expect(popped, 1, reason: 'POP fires once');
  });
}
