import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiupop/core/theme/app_theme.dart';
import 'package:kiupop/features/agent/presentation/kiu_bubble.dart';

import 'helpers.dart';
import 'kiu_flow_test.dart' show reduceMotion, say;

double _contrast(Color a, Color b) {
  final first = a.computeLuminance();
  final second = b.computeLuminance();
  return first >= second
      ? (first + .05) / (second + .05)
      : (second + .05) / (first + .05);
}

void main() {
  test('KiuPop text, controls and logo meet their AA thresholds', () {
    for (final theme in [AppTheme.light(), AppTheme.dark()]) {
      final c = theme.colorScheme;
      for (final (foreground, background) in [
        (c.onPrimary, c.primary),
        (c.primary, c.surfaceContainerLow),
        (c.onSurface, c.surface),
        (c.onSurfaceVariant, c.surfaceContainerLow),
        (c.onSurfaceVariant, c.primaryContainer),
        (c.onPrimaryContainer, c.primaryContainer),
        (c.onTertiaryContainer, c.tertiaryContainer),
        (c.error, c.surface),
        (c.onErrorContainer, c.errorContainer),
        (AppTheme.paper, AppTheme.whatsapp),
      ]) {
        expect(_contrast(foreground, background), greaterThanOrEqualTo(4.5));
      }
      expect(_contrast(c.outline, c.surface), greaterThanOrEqualTo(3));
      expect(_contrast(c.primary, c.surface), greaterThanOrEqualTo(3));
    }
    expect(_contrast(AppTheme.seed, AppTheme.paper), greaterThanOrEqualTo(3));
  });

  for (final (width, height) in [
    (320.0, 640.0),
    (360.0, 720.0),
    (390.0, 844.0),
    (412.0, 892.0),
    (768.0, 1024.0),
    (1024.0, 768.0),
    (1440.0, 900.0),
    (568.0, 320.0),
  ]) {
    testWidgets(
      'onboarding and chat fit ${width.toInt()}×${height.toInt()} at 200%',
      (tester) async {
        reduceMotion(tester);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final auth = FakeAuth();
        await pumpApp(
          tester,
          servicesFor(FakeApi(), FakePlatform(), auth: auth),
          size: Size(width, height),
        );
        expect(tester.takeException(), isNull);
        final welcome = find.byKey(const Key('cta-kiu'));
        await tapVisible(tester, welcome);
        expect(find.text('Creá tu tienda con Kiu'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await auth.registerWithEmail('ui@kiupop.test', 'test123456');
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('intake-voice')), findsOneWidget);
        await chooseWriting(tester);
        final input = find.byKey(const Key('kiu-input'));
        final send = find.byKey(const Key('kiu-send'));
        expect(input.hitTestable(), findsOneWidget);
        expect(tester.getSize(send).shortestSide, greaterThanOrEqualTo(48));
        await tester.showKeyboard(input);
        tester.view.viewInsets = FakeViewPadding(
          bottom: (height < 400 ? 132 : 280) * 3,
        );
        await tester.pumpAndSettle();
        expect(input.hitTestable(), findsOneWidget);
        expect(send.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final (width, height) in [
    (360.0, 640.0),
    (360.0, 780.0),
    (390.0, 844.0),
    (412.0, 915.0),
    (768.0, 1024.0),
    (1440.0, 900.0),
  ]) {
    testWidgets(
      'welcome fits ${width.toInt()}×${height.toInt()} without scrolling',
      (tester) async {
        reduceMotion(tester);
        await pumpApp(
          tester,
          servicesFor(FakeApi(), FakePlatform()),
          size: Size(width, height),
        );
        final scrollable = tester.state<ScrollableState>(
          find.descendant(
            of: find.byKey(const Key('welcome-scroll')),
            matching: find.byType(Scrollable),
          ),
        );
        expect(scrollable.position.maxScrollExtent, 0);
        final cta = tester.getRect(find.byKey(const Key('cta-kiu')));
        expect(cta.bottom, lessThanOrEqualTo(height));
        expect(cta.height, greaterThanOrEqualTo(48));
        expect(find.text('Ya tengo cuenta').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('progress and long task labels wrap at 320px and 200%', (
    tester,
  ) async {
    reduceMotion(tester);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final api = FakeApi()..addProduct('Rosas', 1500000);
    await pumpApp(
      tester,
      servicesFor(api, FakePlatform(), auth: FakeAuth(signedIn: true)),
      at: '/kiu',
      size: const Size(320, 720),
    );
    await say(tester, 'Soy Florería Bella, vendo flores.');
    await say(tester, 'Rosas 15000');
    await say(tester, 'Ambas opciones');
    expect(tester.takeException(), isNull);
    expect(find.text('Descripciones (requiere IA)'), findsOneWidget);
  });

  testWidgets('cart and test checkout fit 320px at 200% in the dark app', (
    tester,
  ) async {
    reduceMotion(tester);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final api = FakeApi()
      ..addProduct(
        'Ramo de rosas de temporada y entrega para celebraciones',
        1500000,
      )
      ..testCheckout = true;
    await pumpApp(
      tester,
      servicesFor(api, FakePlatform()),
      at: '/s/flores-de-occidente',
      size: const Size(320, 640),
    );
    await tester.scrollUntilVisible(find.text('Agregar'), 200);
    await tapVisible(tester, find.text('Agregar').first);
    await tapVisible(tester, find.byKey(const Key('open-cart')));
    expect(find.byKey(const Key('cart-total')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tapVisible(tester, find.byKey(const Key('test-checkout')));
    expect(find.byKey(const Key('checkout-total')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('error suppresses POP and settles a stale animation request', (
    tester,
  ) async {
    var finished = 0;
    Widget host(KiuMood mood, bool pop) => MaterialApp(
      home: KiuBubbleAnimation(
        mood: mood,
        pop: pop,
        onPopped: () => finished++,
      ),
    );
    await tester.pumpWidget(host(KiuMood.error, false));
    await tester.pump(const Duration(seconds: 2));
    expect(finished, 0);
    await tester.pumpWidget(host(KiuMood.error, true));
    expect(finished, 1);
    await tester.pumpWidget(host(KiuMood.success, true));
    await tester.pump(KPopMotion.pop);
    expect(finished, 1);
  });
}
