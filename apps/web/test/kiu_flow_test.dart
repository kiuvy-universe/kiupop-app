import 'dart:convert';

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:kiupop/core/platform/platform_actions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiupop/app.dart';
import 'package:kiupop/core/theme/app_theme.dart';

import 'helpers.dart';

/// Reduced motion keeps pumpAndSettle deterministic (and covers that path).
void reduceMotion(WidgetTester tester) {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

Future<void> say(WidgetTester tester, String text) async {
  await chooseWriting(tester);
  await tester.enterText(find.byKey(const Key('kiu-input')), text);
  await tester.tap(find.byKey(const Key('kiu-send')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('signed-out users are sent to login; email login opens Kiu', (
    tester,
  ) async {
    reduceMotion(tester);
    final api = FakeApi();
    final auth = FakeAuth();
    await pumpApp(
      tester,
      servicesFor(api, FakePlatform(), auth: auth),
      at: '/kiu',
    );
    expect(find.text('Creá tu tienda con Kiu'), findsOneWidget);
    expect(
      find.textContaining('Modo local: cuentas de prueba'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<ButtonStyleButton>(find.byKey(const Key('login-facebook')))
          .onPressed,
      isNull,
      reason: 'Facebook is not faked as working before it is configured',
    );

    await tapVisible(tester, find.text('Ya tengo cuenta · Entrar'));
    await tester.enterText(
      find.byKey(const Key('login-email')),
      'ana@example.test',
    );
    await tester.enterText(
      find.byKey(const Key('login-password')),
      'incorrecta',
    );
    await tapVisible(tester, find.byKey(const Key('login-submit')));
    expect(
      find.text('El correo o la contraseña no coinciden.'),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const Key('login-password')),
      'secreto123',
    );
    await tapVisible(tester, find.byKey(const Key('login-submit')));
    expect(find.textContaining('Soy Kiu'), findsOneWidget);
    expect(auth.calls, ['email']);
  });

  testWidgets('Google sign-in in one tap', (tester) async {
    reduceMotion(tester);
    final auth = FakeAuth();
    await pumpApp(
      tester,
      servicesFor(FakeApi(), FakePlatform(), auth: auth),
      at: '/entrar',
    );
    await tester.tap(find.byKey(const Key('login-google')));
    await tester.pumpAndSettle();
    expect(
      find.text('Cuenta de Google de prueba'),
      findsOneWidget,
      reason: 'local mode never fakes a real Google login',
    );
    await tester.tap(find.byKey(const Key('google-test-continue')));
    await tester.pumpAndSettle();
    expect(auth.calls, ['google']);
    expect(find.textContaining('Soy Kiu'), findsOneWidget);
  });

  testWidgets('talk to Kiu → few questions → POP → confirm → publish → share', (
    tester,
  ) async {
    reduceMotion(tester);
    final api = FakeApi()..addProduct('Ramo de rosas', 1500000);
    final platform = FakePlatform();
    await pumpApp(
      tester,
      servicesFor(api, platform, auth: FakeAuth(signedIn: true)),
      at: '/kiu',
      size: const Size(1280, 860),
    );
    expect(find.text('Kiu te escucha'), findsWidgets);

    await say(tester, 'Soy Florería Bella, vendo flores y arreglos.');
    expect(find.text('¿Cuánto cuestan tus productos?'), findsOneWidget);
    expect(
      find.text('Nunca invento precios.'),
      findsOneWidget,
      reason: 'every question explains why',
    );
    expect(
      find.byKey(const Key('skip-question')),
      findsNothing,
      reason: 'essential questions cannot be skipped',
    );

    await say(tester, 'Ramo de rosas 15000');
    expect(find.byKey(const Key('skip-question')), findsOneWidget);
    await tester.tap(find.byKey(const Key('qr-Ambas opciones')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Estoy terminando tu tienda'), findsOneWidget);

    // The event feed delivers store.ready → POP (reduced motion: instant) → reveal.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('¡POP! Tu tienda ya tomó forma.'), findsWidgets);
    expect(find.text('Ramo de rosas'), findsWidgets);
    expect(find.text('₡15.000'), findsWidgets);

    await tester.tap(find.byKey(const Key('publish-button')));
    await tester.pumpAndSettle();
    expect(find.text('¿Publicamos tu tienda?'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(
      api.kiu.publishCalls,
      0,
      reason: 'publishing needs explicit confirmation',
    );

    await tester.tap(find.byKey(const Key('qr-__publish__')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('publish-confirm')));
    await tester.pumpAndSettle();
    final publish = api.requests.lastWhere(
      (r) => r.url.path.endsWith('/publish'),
    );
    expect(jsonDecode(publish.body), {'confirm': true});
    expect(find.byKey(const Key('share-link')), findsOneWidget);

    await tester.tap(find.byKey(const Key('share-native')));
    await tester.pumpAndSettle();
    expect(
      platform.copied.single,
      'http://localhost:8080/p/flores-de-occidente',
      reason: 'no native share in tests → copy',
    );
    await tester.tap(find.byKey(const Key('share-whatsapp')));
    await tester.pumpAndSettle();
    expect(platform.opened.last.host, 'wa.me');
    expect(
      platform.opened.last.queryParameters['text'],
      contains('/p/flores-de-occidente'),
    );
    await tester.tap(find.byKey(const Key('share-facebook')));
    await tester.pumpAndSettle();
    expect(
      platform.opened.last.toString(),
      startsWith('https://www.facebook.com/sharer/sharer.php'),
    );
  });

  testWidgets('reload resumes the conversation and does not replay POP', (
    tester,
  ) async {
    reduceMotion(tester);
    final api = FakeApi()..addProduct('Ramo de rosas', 1500000);
    api.kiu
      ..exists = true
      ..status = 'ready'
      ..turn = 3;
    api.kiu.messages.add({
      'id': 1,
      'role': 'user',
      'text': 'Soy Florería Bella',
      'meta': <String, Object>{},
      'created_at': '2026-11-22T15:00:00Z',
    });
    await pumpApp(
      tester,
      servicesFor(api, FakePlatform(), auth: FakeAuth(signedIn: true)),
      at: '/kiu',
      size: const Size(1280, 860),
    );
    expect(find.text('Soy Florería Bella'), findsOneWidget);
    expect(find.byKey(const Key('skip-pop')), findsNothing);
    expect(find.byKey(const Key('publish-button')), findsOneWidget);
    expect(
      api.requests.where(
        (r) => r.method == 'POST' && r.url.path == '/api/v1/agent/sessions',
      ),
      isEmpty,
      reason: 'an existing session is resumed, not restarted',
    );
  });

  testWidgets(
    'a ready event included in the initial watermark still plays POP with the keyboard open',
    (tester) async {
      final api = FakeApi()..addProduct('Rosas', 1500000);
      _readyEventAtInitialRead(api.kiu);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 680);
      tester.view.viewInsets = const FakeViewPadding(bottom: 290);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        KiuPopApp(
          services: servicesFor(
            api,
            FakePlatform(),
            auth: FakeAuth(signedIn: true),
          ),
          initialLocation: '/kiu',
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();
      final skip = find.byKey(const Key('skip-pop'));
      final preview = find.byKey(const Key('open-preview'));
      expect(skip, findsOneWidget);
      expect(preview, findsNothing);
      await tester.pump(KPopMotion.pop);
      await tester.pumpAndSettle();
      expect(skip, findsNothing);
      expect(preview, findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(skip, findsNothing);
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      await tapVisible(tester, preview);
      expect(find.text('Vista previa'), findsOneWidget);
      expect(find.text('Agregar'), findsNothing);
      await tapVisible(tester, find.text('Publicar mi tienda').last);
      expect(find.text('¿Publicamos tu tienda?'), findsOneWidget);
      await tapVisible(tester, find.text('Cancelar'));
      expect(api.kiu.publishCalls, 0);
    },
  );

  testWidgets(
    'ready event refresh retries and surfaces a recoverable failure',
    (tester) async {
      reduceMotion(tester);
      final api = FakeApi()..addProduct('Rosas', 1500000);
      _readyEventAtInitialRead(api.kiu);
      api.kiu.readinessReadFailures = 2;
      await pumpApp(
        tester,
        servicesFor(api, FakePlatform(), auth: FakeAuth(signedIn: true)),
        at: '/kiu',
      );
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(find.text('El estado no está disponible.'), findsOneWidget);
      final preview = find.byKey(const Key('open-preview'));
      expect(preview, findsNothing);
      await tapVisible(tester, find.text('Reintentar'));
      expect(preview, findsOneWidget);
      expect(find.text('El estado no está disponible.'), findsNothing);
    },
  );

  testWidgets('an unavailable conversation shows a retry and recovers', (
    tester,
  ) async {
    reduceMotion(tester);
    final api = FakeApi(offline: true);
    await pumpApp(
      tester,
      servicesFor(api, FakePlatform(), auth: FakeAuth(signedIn: true)),
      at: '/kiu',
    );
    expect(
      find.text('No pudimos abrir tu conversación con Kiu'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('kiu-input')), findsNothing);
    api.offline = false;
    await tapVisible(tester, find.text('Reintentar'));
    expect(find.byKey(const Key('intake-chooser')), findsOneWidget);
    await chooseWriting(tester);
    expect(find.byKey(const Key('kiu-input')), findsOneWidget);
  });

  testWidgets('Kiu screen fits a phone', (tester) async {
    reduceMotion(tester);
    await pumpApp(
      tester,
      servicesFor(FakeApi(), FakePlatform(), auth: FakeAuth(signedIn: true)),
      at: '/kiu',
    );
    expect(tester.takeException(), isNull);
    await say(tester, 'Soy Florería Bella, vendo flores.');
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('kiu-bubble')), findsOneWidget);
  });

  testWidgets('a session the provider revoked sends the user back to login', (
    tester,
  ) async {
    reduceMotion(tester);
    final api = FakeApi();
    final auth = RevokedAuth();
    await pumpApp(
      tester,
      servicesFor(api, FakePlatform(), auth: auth),
      at: '/kiu',
    );
    expect(auth.forced, isTrue, reason: 'a 401 triggers one forced refresh');
    expect(find.text('Creá tu tienda con Kiu'), findsOneWidget);
  });
  testWidgets('share photos with Kiu: per-file status, limits checked first', (
    tester,
  ) async {
    reduceMotion(tester);
    final api = FakeApi();
    final platform = FakePlatform()
      ..nextFiles = [
        PickedFile('ramo.png', tinyPng()),
        PickedFile('enorme.pdf', Uint8List(21 << 20)),
      ];
    await pumpApp(
      tester,
      servicesFor(api, platform, auth: FakeAuth(signedIn: true)),
      at: '/kiu',
    );
    await chooseWriting(tester);
    await tester.tap(find.byKey(const Key('kiu-attach')));
    await tester.pumpAndSettle();
    expect(find.textContaining('ramo.png · listo'), findsOneWidget);
    expect(
      find.textContaining('enorme.pdf: es demasiado grande'),
      findsOneWidget,
    );
    final uploads = api.requests.where(
      (r) => r.url.path.endsWith('/attachments'),
    );
    expect(
      uploads,
      hasLength(1),
      reason: 'the oversized file never leaves the browser',
    );
  });
  testWidgets('voice: transcript lands in the input to review before sending', (
    tester,
  ) async {
    reduceMotion(tester);
    final api = FakeApi();
    final platform = FakePlatform();
    await pumpApp(
      tester,
      servicesFor(api, platform, auth: FakeAuth(signedIn: true)),
      at: '/kiu',
    );
    await chooseWriting(tester);
    await tester.tap(find.byKey(const Key('kiu-mic')));
    await tester.pump();
    platform.dictate!('Soy Florería Bella vendo flores', true);
    await tester.tap(find.byKey(const Key('kiu-mic'))); // stop
    await tester.pumpAndSettle();
    expect(find.text('Soy Florería Bella vendo flores'), findsOneWidget);
    expect(
      api.requests.where((r) => r.url.path.endsWith('/messages')),
      isEmpty,
      reason: 'nothing is sent until the merchant taps send',
    );
  });
}

/// Hands out a token the API rejects, even after a forced refresh.
class RevokedAuth extends FakeAuth {
  RevokedAuth() : super(signedIn: true);
  bool forced = false;
  @override
  Future<String?> idToken({bool force = false}) async {
    forced = forced || force;
    return currentUser == null ? null : 'revoked.token.value-for-tests';
  }
}

void _readyEventAtInitialRead(FakeKiu kiu) {
  kiu
    ..exists = true
    ..status = 'building'
    ..turn = 3;
  kiu.messages.add({
    'id': 1,
    'role': 'user',
    'text': 'Soy Florería Bella',
    'meta': <String, Object>{},
    'created_at': '2026-11-22T15:00:00Z',
  });
  kiu.events.add({
    'id': kiu.eventId,
    'type': 'store.ready',
    'payload': <String, Object>{},
    'created_at': '2026-11-22T15:00:00Z',
  });
}
