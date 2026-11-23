import 'dart:io' show Platform;

import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// A running dictation.
abstract class Dictation {
  void stop();
}

final _stt = SpeechToText();

// The callbacks of the dictation in progress (the plugin keeps one listener).
void Function()? _onEnd;
void Function(String code)? _onError;

/// Android/iOS: the system speech recognizer (asks for the microphone once).
bool dictationAvailable() => Platform.isAndroid || Platform.isIOS;

class _NativeDictation implements Dictation {
  bool stopped = false;
  @override
  void stop() {
    stopped = true;
    _stt.stop();
  }
}

/// Starts recognition; text arrives as it is heard and stays editable.
Dictation? startDictation({
  required String lang,
  required void Function(String text, bool isFinal) onText,
  required void Function() onEnd,
  required void Function(String code) onError,
}) {
  if (!dictationAvailable()) return null;
  final d = _NativeDictation();
  _onEnd = onEnd;
  _onError = onError;
  () async {
    final ok = await _stt.initialize(
      onError: (SpeechRecognitionError e) {
        if (e.permanent) _onError?.call(_code(e.errorMsg));
      },
      onStatus: (s) {
        if (s == SpeechToText.doneStatus) _onEnd?.call();
      },
    );
    if (!ok) {
      onError(await _stt.hasPermission ? 'unavailable' : 'not-allowed');
      return;
    }
    if (d.stopped) return;
    await _stt.listen(
      onResult: (SpeechRecognitionResult r) =>
          onText(r.recognizedWords.trim(), r.finalResult),
      listenOptions: SpeechListenOptions(
        partialResults: true,
        localeId: lang.replaceAll('-', '_'),
      ),
    );
  }();
  return d;
}

String _code(String msg) => msg.contains('permission') ? 'not-allowed' : msg;
