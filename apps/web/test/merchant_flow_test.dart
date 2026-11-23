import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  testWidgets('welcome shows the promise and the main action', (tester) async {
    await pumpApp(tester, servicesFor(FakeApi(), FakePlatform()));
    expect(find.text('Tu tienda empieza con una idea.'), findsOneWidget);
    expect(find.text('Crear mi tienda'), findsOneWidget);
    expect(find.text('Ya tengo cuenta'), findsOneWidget);
    // One screen, one intention: secondary paths live one step further.
    expect(
      find.text('Entrar con una clave kp_ (tiendas del POC)'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
    await tapVisible(tester, find.text('Ya tengo cuenta'));
    expect(
      find.text('Entrar con una clave kp_ (tiendas del POC)'),
      findsOneWidget,
    );
    expect(
      find.text('¿Solo querés mirar? Ver una tienda de ejemplo'),
      findsOneWidget,
    );
  });

  testWidgets('create store → credential shown once → admin with empty state', (
    tester,
  ) async {
    final api = FakeApi();
    final platform = FakePlatform();
    // The POC form flow is kept at /crear (Kiu is the main path now).
    await pumpApp(tester, servicesFor(api, platform), at: '/crear');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nombre del negocio'),
      'Flores de Occidente',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'WhatsApp para recibir pedidos'),
      '+506 0000 0001',
    );
    await tester.tap(find.text('Crear mi tienda'));
    await tester.pumpAndSettle();

    expect(find.text('¡Tu tienda está lista!'), findsOneWidget);
    expect(find.byKey(const Key('admin-token')), findsOneWidget);
    expect(
      find.text('http://localhost:3000/#/s/flores-de-occidente'),
      findsOneWidget,
    );

    // Credential never travels in a URL.
    expect(
      api.requests.any((r) => r.url.toString().contains(api.token)),
      isFalse,
    );

    await tester.tap(find.text('Copiar clave'));
    await tester.pumpAndSettle();
    expect(platform.copied, [api.token]);

    final cont = find.widgetWithText(FilledButton, 'Continuar a mis productos');
    expect(
      tester.widget<FilledButton>(cont).onPressed,
      isNull,
      reason: 'must confirm saving first',
    );
    await tester.tap(find.text('Ya guardé mi clave'));
    await tester.pumpAndSettle();
    await tester.tap(cont);
    await tester.pumpAndSettle();

    expect(find.text('Agrega tu primer producto'), findsOneWidget);
    expect(find.text('Agregar producto'), findsOneWidget);
    expect(api.requests.last.headers['Authorization'], 'Bearer ${api.token}');
  });

  testWidgets('client-side validation errors do not call the API', (
    tester,
  ) async {
    final api = FakeApi();
    await pumpApp(tester, servicesFor(api, FakePlatform()), at: '/crear');
    await tester.tap(find.text('Crear mi tienda'));
    await tester.pumpAndSettle();
    expect(
      find.text('Escribe el nombre de tu negocio (mínimo 2 letras).'),
      findsOneWidget,
    );
    expect(find.text('Escribe un número de WhatsApp válido.'), findsOneWidget);
    expect(api.requests, isEmpty);
  });

  testWidgets(
    'admin route without session redirects to sign in; bad key shows error',
    (tester) async {
      final api = FakeApi();
      await pumpApp(tester, servicesFor(api, FakePlatform()), at: '/admin');
      expect(find.text('Entrar a mi tienda'), findsOneWidget);
      await tester.enterText(
        find.byType(TextField),
        'kp_wrong_wrong_wrong_wrong_wrong',
      );
      await tester.tap(find.text('Entrar'));
      await tester.pumpAndSettle();
      expect(
        find.text('La clave no es válida. Revisa que la copiaste completa.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('add product with photo; AI disabled is explained', (
    tester,
  ) async {
    final api = FakeApi();
    final platform = FakePlatform()..nextImage = null;
    final services = servicesFor(api, platform);
    await pumpApp(tester, services, at: '/clave');
    await tester.enterText(find.byType(TextField), api.token);
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Agregar producto'));
    await tester.pumpAndSettle();
    expect(find.textContaining('KiuPop AI no está disponible'), findsOneWidget);
    expect(find.text('Mejorar con IA'), findsNothing);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nombre'),
      'Rosa roja',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Precio en colones'),
      '2.000',
    );
    await tester.tap(find.text('Guardar producto'));
    await tester.pumpAndSettle();

    expect(api.products.single['price_minor'], 200000);
    expect(find.text('Rosa roja'), findsOneWidget);
    expect(find.text('₡2.000'), findsOneWidget);
  });

  testWidgets('KiuPop AI proposal is reviewed and accepted; price untouched', (
    tester,
  ) async {
    final api = FakeApi(aiEnabled: true);
    await pumpApp(tester, servicesFor(api, FakePlatform()), at: '/clave');
    await tester.enterText(find.byType(TextField), api.token);
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agregar producto'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Precio en colones'),
      '2000',
    );
    await tester.enterText(
      find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.hintText == 'Ej.: Rosa roja natural para regalo',
      ),
      'Rosa roja natural para regalo, cuesta 2000 colones',
    );
    await tester.tap(find.text('Mejorar con IA'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ai-suggestion')), findsOneWidget);
    expect(
      find.text('El precio no lo cambia la IA: lo pones tú.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Usar esta propuesta'));
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(TextFormField, 'Rosa roja natural'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextFormField, '2000'), findsOneWidget);
    final aiCall = api.requests.firstWhere(
      (r) => r.url.path.endsWith('/ai/product-description'),
    );
    expect(aiCall.body.contains('price'), isFalse);
  });
}
