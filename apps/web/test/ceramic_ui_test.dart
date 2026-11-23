import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiupop/core/theme/app_theme.dart';
import 'package:kiupop/core/widgets/kpop_components.dart';
import 'package:kiupop/features/agent/presentation/kiu_bubble.dart';
import 'package:kiupop/features/stores/data/store_models.dart';

import 'helpers.dart';
import 'kiu_flow_test.dart' show reduceMotion;

double _contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return x > y ? (x + .05) / (y + .05) : (y + .05) / (x + .05);
}

/// KPOP-UX-002: the settings sheet, the store peek after the POP and the
/// ceramic components keep every action reachable.
void main() {
  testWidgets('settings: appearance, how Kiu thinks and sign out', (
    tester,
  ) async {
    reduceMotion(tester);
    final auth = FakeAuth(signedIn: true);
    final services = servicesFor(FakeApi(), FakePlatform(), auth: auth);
    await pumpApp(tester, services, at: '/kiu');
    await tapVisible(tester, find.byKey(const Key('open-settings')));
    expect(find.text('Ajustes'), findsOneWidget);
    expect(find.text('Modo local'), findsOneWidget);
    await tapVisible(tester, find.text('Oscuro'));
    expect(services.theme.mode, ThemeMode.dark);
    expect(
      Theme.of(tester.element(find.text('Ajustes'))).brightness,
      Brightness.dark,
    );
    await tapVisible(tester, find.text('Claro'));
    expect(services.theme.mode, ThemeMode.light);
    await tapVisible(tester, find.byTooltip('Cerrar').last);
    expect(find.text('Ajustes'), findsNothing);
    await tapVisible(tester, find.byKey(const Key('open-settings')));
    await tapVisible(tester, find.byKey(const Key('sign-out')));
    expect(auth.currentUser, isNull);
    expect(find.byKey(const Key('cta-kiu')), findsOneWidget);
  });

  testWidgets('admin: sign out lives in settings', (tester) async {
    reduceMotion(tester);
    final services = servicesFor(FakeApi(), FakePlatform());
    services.session.signIn(
      token: 'kp_test_token_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      store: const AdminStore(
        id: '6f1d2c3b-4a59-4e8f-9a0b-1c2d3e4f5a6b',
        slug: 'flores-de-occidente',
        name: 'Flores de Occidente',
        description: '',
        whatsapp: '50600000001',
      ),
      aiEnabled: false,
    );
    await pumpApp(tester, services, at: '/admin');
    expect(find.text('Flores de Occidente'), findsWidgets);
    await tapVisible(tester, find.byKey(const Key('open-settings')));
    expect(find.text('Modo local'), findsNothing);
    await tapVisible(tester, find.byKey(const Key('sign-out')));
    expect(services.session.isSignedIn, isFalse);
    expect(find.byKey(const Key('cta-kiu')), findsOneWidget);
  });

  testWidgets('after the POP the store peeks in and opens the preview', (
    tester,
  ) async {
    reduceMotion(tester);
    final api = FakeApi()..addProduct('Rosas', 1500000);
    api.kiu
      ..exists = true
      ..status = 'building'
      ..turn = 3;
    api.kiu.messages.add({
      'id': 1,
      'role': 'user',
      'text': 'Soy Florería Bella',
      'meta': <String, Object>{},
      'created_at': '2026-11-22T15:00:00Z',
    });
    api.kiu.events.add({
      'id': api.kiu.eventId,
      'type': 'store.ready',
      'payload': <String, Object>{},
      'created_at': '2026-11-22T15:00:00Z',
    });
    await pumpApp(
      tester,
      servicesFor(api, FakePlatform(), auth: FakeAuth(signedIn: true)),
      at: '/kiu',
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(find.text('¡POP! Tu tienda ya tomó forma.'), findsWidgets);
    expect(find.byKey(const Key('open-preview')), findsOneWidget);
    final peek = find.byKey(const Key('store-peek'));
    expect(peek, findsOneWidget);
    await tapVisible(tester, peek);
    expect(find.text('Vista previa'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ceramic components render their tones and tints', (
    tester,
  ) async {
    var taps = 0;
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                for (final tone in KPopButtonTone.values)
                  KPopButton(
                    label: tone.name,
                    icon: Icons.star_rounded,
                    tone: tone,
                    onPressed: () => taps++,
                  ),
                for (final tone in KPopButtonTone.values)
                  KPopButton(
                    label: 'plain ${tone.name}',
                    tone: tone,
                    onPressed: null,
                  ),
                KPopSurface(
                  onTap: () => taps++,
                  raised: true,
                  child: const Text('surface'),
                ),
                const KPopCard(flat: true, child: Text('flat card')),
                const KPopBanner(text: 'banner', tint: KPopTint.mint),
                const KPopClayTile(
                  tint: KPopTint.peach,
                  icon: Icons.local_florist_outlined,
                  label: 'tile',
                  subtitle: 'detail',
                ),
                const KPopIconBubble(icon: Icons.add, tint: KPopTint.babyBlue),
                KPopChip(label: 'chip', onPressed: () => taps++),
              ],
            ),
          ),
        ),
      ),
    );
    for (final tone in KPopButtonTone.values) {
      await tester.tap(find.text(tone.name));
    }
    await tester.tap(find.text('surface'));
    await tester.tap(find.text('chip'));
    expect(taps, KPopButtonTone.values.length + 2);
    for (final scheme in [
      AppTheme.light().colorScheme,
      AppTheme.dark().colorScheme,
    ]) {
      for (final tint in KPopTint.values) {
        expect(
          _contrast(tint.foreground(scheme), tint.background(scheme)),
          greaterThanOrEqualTo(4.5),
          reason: '$tint in ${scheme.brightness}',
        );
      }
    }
  });

  testWidgets('a POP that arrives while covered waits and then plays', (
    tester,
  ) async {
    var finished = 0;
    Widget host({required bool visible}) => MaterialApp(
      home: TickerMode(
        enabled: visible,
        child: KiuBubbleAnimation(
          mood: KiuMood.success,
          progress: 1,
          pop: true,
          onPopped: () => finished++,
        ),
      ),
    );
    await tester.pumpWidget(host(visible: false));
    await tester.pump(KPopMotion.pop * 2);
    expect(finished, 0, reason: 'not consumed while nobody can see it');
    await tester.pumpWidget(host(visible: true));
    await tester.pump(KPopMotion.pop * .5);
    expect(finished, 0);
    await tester.pump(KPopMotion.pop);
    expect(finished, 1);
  });

  testWidgets('waiting for the merchant, Kiu breathes once and rests', (
    tester,
  ) async {
    await pumpApp(
      tester,
      servicesFor(FakeApi(), FakePlatform(), auth: FakeAuth(signedIn: true)),
      at: '/kiu',
    );
    expect(find.byType(KiuBubbleAnimation), findsOneWidget);
    await tester.pump(KPopMotion.floatCycle + const Duration(seconds: 2));
    expect(tester.hasRunningAnimations, isFalse);
    expect(find.text('Kiu te escucha'), findsOneWidget);
  });

  for (final width in [320.0, 360.0]) {
    testWidgets('settings sheet fits ${width.toInt()} dp at 200 % text', (
      tester,
    ) async {
      reduceMotion(tester);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpApp(
        tester,
        servicesFor(FakeApi(), FakePlatform(), auth: FakeAuth(signedIn: true)),
        at: '/kiu',
        size: Size(width, 720),
      );
      await tapVisible(tester, find.byKey(const Key('open-settings')));
      expect(tester.takeException(), isNull);
      for (final label in ['Automático', 'Claro', 'Oscuro']) {
        await tester.ensureVisible(find.text(label));
        expect(find.text(label).hitTestable(), findsOneWidget);
      }
      await tester.ensureVisible(find.byKey(const Key('sign-out')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sign-out')).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a failed sign out is visible and keeps the session', (
    tester,
  ) async {
    reduceMotion(tester);
    final auth = _FailingSignOut();
    await pumpApp(
      tester,
      servicesFor(FakeApi(), FakePlatform(), auth: auth),
      at: '/kiu',
    );
    await tapVisible(tester, find.byKey(const Key('open-settings')));
    await tapVisible(tester, find.byKey(const Key('sign-out')));
    expect(find.text('Algo salió mal. Intenta de nuevo.'), findsOneWidget);
    expect(auth.currentUser, isNotNull);
    expect(find.byKey(const Key('intake-chooser')), findsOneWidget);
  });

  for (final (label, landing) in [
    ('¿Solo querés mirar? Ver una tienda de ejemplo', 'tienda-demo'),
    ('Entrar con una clave kp_ (tiendas del POC)', 'Entrar a mi tienda'),
  ]) {
    testWidgets('paths moved off welcome stay one tap away: $landing', (
      tester,
    ) async {
      reduceMotion(tester);
      final api = FakeApi();
      await pumpApp(
        tester,
        servicesFor(api, FakePlatform()),
        size: const Size(360, 720),
      );
      await tapVisible(tester, find.text('Ya tengo cuenta'));
      await tapVisible(tester, find.text(label));
      if (landing == 'tienda-demo') {
        expect(
          api.requests.any((r) => r.url.path.contains('tienda-demo')),
          isTrue,
        );
      } else {
        expect(find.text(landing), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }
}

class _FailingSignOut extends FakeAuth {
  _FailingSignOut() : super(signedIn: true);
  @override
  Future<void> signOut() async => throw StateError('network');
}
