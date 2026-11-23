@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiupop/core/theme/app_theme.dart';
import 'package:kiupop/features/agent/presentation/kiu_bubble.dart';

/// Kiu's identity and state machine, frozen as images (KPOP-UX-002):
/// ceramic body, orb hands, bubblegum that grows with confirmed progress and
/// a POP that only plays when requested. No text, so the images do not
/// depend on fonts.
void main() {
  Future<void> host(
    WidgetTester tester, {
    KiuMood mood = KiuMood.idle,
    double progress = 0,
    bool pop = false,
    bool reduced = false,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = const Size(240, 240);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: brightness == Brightness.light
            ? AppTheme.light()
            : AppTheme.dark(),
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(240, 240),
            disableAnimations: reduced,
          ),
          child: RepaintBoundary(
            key: const Key('kiu'),
            child: ColoredBox(
              color: brightness == Brightness.light
                  ? KPopColors.cream
                  : KPopColors.night,
              child: Center(
                child: KiuBubbleAnimation(
                  mood: mood,
                  progress: progress,
                  pop: pop,
                  size: 220,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> expectKiu(WidgetTester tester, String name) => expectLater(
    find.byKey(const Key('kiu')),
    matchesGoldenFile('goldens/kiu_$name.png'),
  );

  testWidgets('idle', (tester) async {
    await host(tester);
    await tester.pump(KPopMotion.floatCycle);
    await expectKiu(tester, 'idle');
  });

  testWidgets('listening', (tester) async {
    await host(tester, mood: KiuMood.listening);
    await tester.pump(const Duration(milliseconds: 1300));
    await expectKiu(tester, 'listening');
  });

  testWidgets('thinking', (tester) async {
    await host(tester, mood: KiuMood.thinking);
    await tester.pump(const Duration(milliseconds: 600));
    await expectKiu(tester, 'thinking');
  });

  testWidgets('building at 30 % and 85 %', (tester) async {
    await host(tester, mood: KiuMood.processing, progress: .30);
    await tester.pump(KPopMotion.slow);
    await expectKiu(tester, 'building_30');
    await host(tester, mood: KiuMood.processing, progress: .85);
    await tester.pump(KPopMotion.slow);
    await tester.pump(KPopMotion.slow);
    await expectKiu(tester, 'building_85');
  });

  testWidgets('bubble swell and POP', (tester) async {
    await host(tester, mood: KiuMood.processing, progress: 1);
    await tester.pump(KPopMotion.slow);
    await host(tester, mood: KiuMood.success, progress: 1, pop: true);
    await tester.pump(KPopMotion.pop * .30);
    await expectKiu(tester, 'pop_swell');
    await tester.pump(KPopMotion.pop * .25);
    await expectKiu(tester, 'pop_burst');
    await tester.pump(KPopMotion.pop * .25);
    await expectKiu(tester, 'celebrating');
  });

  testWidgets('error never celebrates', (tester) async {
    await host(tester, mood: KiuMood.error);
    await tester.pump();
    await expectKiu(tester, 'error');
  });

  testWidgets('reduced motion is a still, finished frame', (tester) async {
    await host(tester, mood: KiuMood.processing, progress: .6, reduced: true);
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
    await expectKiu(tester, 'reduced_motion');
  });

  testWidgets('dark theme', (tester) async {
    await host(tester, mood: KiuMood.greeting, brightness: Brightness.dark);
    await tester.pump(const Duration(milliseconds: 500));
    await expectKiu(tester, 'dark_greeting');
  });

  testWidgets('resting moods breathe once and then hold still', (tester) async {
    await host(tester, mood: KiuMood.success);
    await tester.pump(KPopMotion.floatCycle + KPopMotion.fast);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await host(tester, mood: KiuMood.listening);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.hasScheduledFrame, isTrue);
  });
}
