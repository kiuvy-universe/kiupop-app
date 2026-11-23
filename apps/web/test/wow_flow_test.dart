import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiupop/core/platform/platform_actions.dart';
import 'package:kiupop/features/voice/data/wav.dart';

import 'helpers.dart';
import 'kiu_flow_test.dart' show reduceMotion, say;

/// KPOP-WOW-001: talk or write → voice note reviewed before Kiu → files with
/// progress, cancel and retry → reveal → funnel milestones.
void main() {
  test('WAV header wraps 16 kHz mono PCM', () {
    final wav = wavFromPcm16(Uint8List(32000));
    final b = ByteData.sublistView(wav);
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    expect(b.getUint32(24, Endian.little), 16000);
    expect(b.getUint16(22, Endian.little), 1);
    expect(b.getUint32(40, Endian.little), 32000);
    expect(pcmDuration(32000), const Duration(seconds: 1));
  });

  testWidgets('talk to Kiu: record, listen, transcribe, correct, send', (
    tester,
  ) async {
    reduceMotion(tester);
    final api = FakeApi()..speechEnabled = true;
    final voice = FakeVoice();
    await pumpApp(
      tester,
      servicesFor(
        api,
        FakePlatform(),
        auth: FakeAuth(signedIn: true),
        voice: voice.io,
      ),
      at: '/kiu',
    );
    expect(find.text('¿Cómo querés contarle tu idea a Kiu?'), findsOneWidget);
    expect(
      find.text(
        'Contame qué imaginás. Crear tu primera propuesta no tiene costo.',
      ),
      findsOneWidget,
    );
    await tapVisible(tester, find.byKey(const Key('intake-voice')));
    expect(find.byKey(const Key('voice-sheet')), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('voice-record')));
    expect(find.byKey(const Key('voice-clock')), findsOneWidget);
    voice.speak(3.2);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('0:03'), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('voice-stop')));
    expect(find.textContaining('Nota de voz · 0:03'), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('voice-play')));
    expect(voice.played.single, 44 + 3.2 * 32000);
    await tapVisible(tester, find.byKey(const Key('voice-transcribe')));
    expect(api.transcribedBytes.single, 44 + 3.2 * 32000);
    expect(find.text('Esto entendí'), findsOneWidget);
    expect(
      find.text(
        'Transcripción con Google Speech-to-Text. El audio no se guarda.',
      ),
      findsOneWidget,
    );
    // The merchant fixes a price before Kiu sees it.
    await tester.enterText(
      find.byKey(const Key('voice-transcript')),
      'Soy Dulce Luna, vendo queques de naranja a 6500 y galletas a 3000.',
    );
    await tapVisible(tester, find.byKey(const Key('voice-send')));
    expect(find.byKey(const Key('voice-sheet')), findsNothing);
    expect(find.textContaining('galletas a 3000'), findsWidgets);
    final events = [for (final e in api.funnelEvents) e['event']];
    expect(events, containsAll(['intake_method_selected', 'audio_recorded']));
    final intake = api.funnelEvents.firstWhere(
      (e) => e['event'] == 'intake_method_selected',
    );
    expect(intake['meta'], {'method_audio': 1});
    expect(tester.takeException(), isNull);
  });

  testWidgets('voice errors are clear and typing is always one tap away', (
    tester,
  ) async {
    reduceMotion(tester);
    final api = FakeApi()
      ..speechEnabled = true
      ..speechFailStatus = 422
      ..speechFailCode = 'audio_silent';
    final voice = FakeVoice()..permission = false;
    await pumpApp(
      tester,
      servicesFor(
        api,
        FakePlatform(),
        auth: FakeAuth(signedIn: true),
        voice: voice.io,
      ),
      at: '/kiu',
    );
    await tapVisible(tester, find.byKey(const Key('intake-voice')));
    await tapVisible(tester, find.byKey(const Key('voice-record')));
    expect(
      find.textContaining('permiso para usar el micrófono'),
      findsOneWidget,
    );

    // Permission granted, but the clip is too short.
    voice.permission = true;
    await tapVisible(tester, find.text('Reintentar'));
    await tapVisible(tester, find.byKey(const Key('voice-record')));
    voice.speak(.3);
    await tester.pump(const Duration(milliseconds: 300));
    await tapVisible(tester, find.byKey(const Key('voice-stop')));
    expect(
      find.text('El audio quedó muy corto. Contame un poco más.'),
      findsOneWidget,
    );

    // A real clip the server finds silent: its message, then retry.
    await tapVisible(tester, find.text('Reintentar'));
    await tapVisible(tester, find.byKey(const Key('voice-record')));
    voice.speak(2);
    await tester.pump(const Duration(milliseconds: 300));
    await tapVisible(tester, find.byKey(const Key('voice-stop')));
    await tapVisible(tester, find.byKey(const Key('voice-transcribe')));
    expect(find.text('No te escuché. Probá de nuevo.'), findsOneWidget);
    api.speechFailStatus = null;
    await tapVisible(tester, find.text('Reintentar'));
    expect(find.text('Esto entendí'), findsOneWidget);
    // An emptied transcript is not sent.
    await tester.enterText(find.byKey(const Key('voice-transcript')), '  ');
    await tapVisible(tester, find.byKey(const Key('voice-send')));
    expect(
      find.text('Escribí o corregí el texto antes de enviarlo.'),
      findsOneWidget,
    );
    // Typing instead.
    await tapVisible(tester, find.byTooltip('Cerrar'));
    expect(find.byKey(const Key('kiu-input')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('without a transcription provider, voice says so honestly', (
    tester,
  ) async {
    reduceMotion(tester);
    final api = FakeApi(); // speech disabled
    await pumpApp(
      tester,
      servicesFor(api, FakePlatform(), auth: FakeAuth(signedIn: true)),
      at: '/kiu',
    );
    expect(find.textContaining('Audio no disponible ahora'), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('intake-voice')));
    expect(find.byKey(const Key('voice-sheet')), findsNothing);
    expect(
      find.text(
        'La transcripción de audio no está disponible ahora. Podés escribirle a Kiu.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('kiu-input')), findsOneWidget);
    expect(find.byKey(const Key('kiu-voice')), findsNothing);
  });

  testWidgets('files: total bytes checked first, progress, cancel and retry', (
    tester,
  ) async {
    reduceMotion(tester);
    final api = FakeApi()..holdUploads = Completer<void>();
    final platform = FakePlatform()
      ..nextFiles = [
        PickedFile(
          'catalogo.csv',
          Uint8List.fromList('Rosas,15000\n'.codeUnits),
        ),
        PickedFile('fotos-grandes.pdf', Uint8List(19 << 20)),
        PickedFile('mas-fotos.pdf', Uint8List(19 << 20)),
        PickedFile('ultimo.pdf', Uint8List(19 << 20)),
      ];
    await pumpApp(
      tester,
      servicesFor(api, platform, auth: FakeAuth(signedIn: true)),
      at: '/kiu',
    );
    await say(tester, 'Soy Florería Bella, vendo flores.');
    await tester.tap(find.byKey(const Key('kiu-attach')));
    await tester.pump();
    // 3 × 19 MB > 50 MB: the third PDF is refused before any upload.
    expect(find.textContaining('superás los 50 MB'), findsOneWidget);
    expect(find.textContaining('Subiendo'), findsNWidgets(3));
    final cancel = find.byTooltip('Cancelar subida de mas-fotos.pdf');
    await tester.ensureVisible(cancel);
    await tester.pump();
    expect(cancel.hitTestable(), findsOneWidget);
    await tester.tap(cancel);
    await tester.pump();
    api.uploadFailures = 1;
    api.holdUploads!.complete();
    api.holdUploads = null;
    await tester.pumpAndSettle();
    expect(
      find.textContaining('mas-fotos.pdf'),
      findsNothing,
      reason: 'cancelled',
    );
    final retry = find.textContaining('Reintentar');
    expect(retry, findsOneWidget, reason: 'one upload failed');
    await tapVisible(tester, retry);
    expect(find.textContaining('Reintentar'), findsNothing);
    expect(find.textContaining('Subiendo'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('after the POP: explore, adjust or continue', (tester) async {
    reduceMotion(tester);
    final api = FakeApi()..addProduct('Ramo de rosas', 1500000);
    await pumpApp(
      tester,
      servicesFor(api, FakePlatform(), auth: FakeAuth(signedIn: true)),
      at: '/kiu',
    );
    await say(tester, 'Soy Florería Bella, vendo flores y arreglos.');
    await say(tester, 'Ramo de rosas 15000');
    await tester.tap(find.byKey(const Key('qr-Ambas opciones')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('¡POP! Tu tienda ya tomó forma.'), findsWidgets);
    expect(
      find.text(
        'Kiu organizó tu negocio y preparó una tienda diseñada para vos.',
      ),
      findsWidgets,
    );
    await tapVisible(tester, find.byKey(const Key('adjust-store')));
    expect(
      find.text('Contale a Kiu qué querés cambiar: colores, nombres, precios…'),
      findsOneWidget,
    );
    await tapVisible(tester, find.byKey(const Key('open-preview')));
    expect(find.text('Vista previa'), findsOneWidget);
    Navigator.of(tester.element(find.text('Vista previa'))).pop();
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('continue-publish')));
    expect(
      find.byKey(const Key('paywall-sheet')).evaluate().isNotEmpty ||
          find.text('¿Publicamos tu tienda?').evaluate().isNotEmpty,
      isTrue,
    );
    expect([
      for (final e in api.funnelEvents) e['event'],
    ], containsAll(['intake_method_selected', 'store_preview_opened']));
  });
}
