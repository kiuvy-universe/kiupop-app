import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  testWidgets('catalog → cart → server-priced order → WhatsApp opens', (
    tester,
  ) async {
    final api = FakeApi()
      ..addProduct('Rosa roja', 100000)
      ..addProduct('Arreglo pequeño', 500000)
      ..addProduct('Girasol', 90000, available: false);
    final platform = FakePlatform();
    await pumpApp(
      tester,
      servicesFor(api, platform),
      at: '/s/flores-de-occidente',
    );

    expect(find.text('Flores de Occidente'), findsOneWidget);
    expect(find.text('Rosa roja'), findsOneWidget);
    expect(
      find.text('Girasol'),
      findsNothing,
      reason: 'unavailable products are not listed',
    );

    await tapVisible(tester, find.text('Agregar').first);
    await tapVisible(tester, find.byTooltip('Agregar uno de Rosa roja'));
    await tapVisible(tester, find.text('Agregar').first); // Arreglo
    expect(find.text('Ver pedido · 3 productos'), findsOneWidget);

    await tester.tap(find.byKey(const Key('open-cart')));
    await tester.pumpAndSettle();
    expect(find.text('₡7.000'), findsWidgets);
    expect(
      find.textContaining('Aún no se ha realizado ningún pago'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('order-whatsapp')));
    await tester.pumpAndSettle();

    final preview = api.requests.last;
    expect(
      preview.url.path,
      '/api/v1/public/stores/flores-de-occidente/orders/preview',
    );
    final items = (jsonDecode(preview.body) as Map)['items'] as List;
    expect(
      items.every(
        (i) =>
            (i as Map).keys.toSet().containsAll({'product_id', 'quantity'}) &&
            i.length == 2,
      ),
      isTrue,
      reason: 'only ids and quantities are sent, never prices',
    );
    expect(preview.headers.containsKey('Authorization'), isFalse);
    expect(
      platform.opened.single.toString(),
      'https://wa.me/50600000001?text=Hola',
    );
    expect(find.textContaining('Abrimos WhatsApp'), findsOneWidget);
  });

  testWidgets('empty catalog shows a friendly state', (tester) async {
    await pumpApp(
      tester,
      servicesFor(FakeApi(), FakePlatform()),
      at: '/s/flores-de-occidente',
    );
    expect(find.text('Pronto habrá productos aquí'), findsOneWidget);
  });

  testWidgets('unknown store shows not found', (tester) async {
    await pumpApp(
      tester,
      servicesFor(FakeApi(), FakePlatform()),
      at: '/s/no-existe',
    );
    expect(find.text('No encontramos esta tienda'), findsOneWidget);
  });

  testWidgets('network error shows retry and recovers', (tester) async {
    final api = FakeApi(offline: true)..addProduct('Rosa roja', 100000);
    await pumpApp(
      tester,
      servicesFor(api, FakePlatform()),
      at: '/s/flores-de-occidente',
    );
    expect(find.text('No pudimos cargar el catálogo'), findsOneWidget);
    api.offline = false;
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.text('Rosa roja'), findsOneWidget);
  });

  testWidgets('catalog fits a 360 px phone and a desktop without overflow', (
    tester,
  ) async {
    final api = FakeApi();
    for (var i = 0; i < 6; i++) {
      api.addProduct(
        'Producto con un nombre bastante largo número $i',
        123456700,
      );
    }
    for (final size in const [Size(360, 740), Size(1280, 800)]) {
      await pumpApp(
        tester,
        servicesFor(api, FakePlatform()),
        at: '/s/flores-de-occidente',
        size: size,
      );
      expect(tester.takeException(), isNull, reason: 'overflow at $size');
    }
  });
}
