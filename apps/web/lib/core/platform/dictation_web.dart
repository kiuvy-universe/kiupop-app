import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// A running dictation.
abstract class Dictation {
  void stop();
}

JSFunction? _ctor() {
  final w = globalContext;
  final c = w['SpeechRecognition'] ?? w['webkitSpeechRecognition'];
  return c.isA<JSFunction>() ? c as JSFunction : null;
}

/// Whether the browser offers speech recognition (Chrome, Edge, Safari).
bool dictationAvailable() => _ctor() != null;

class _WebDictation implements Dictation {
  _WebDictation(this._rec);
  final JSObject _rec;
  @override
  void stop() => _rec.callMethod('stop'.toJS);
}

/// Starts the browser recognizer (asks for microphone permission the first time).
Dictation? startDictation({
  required String lang,
  required void Function(String text, bool isFinal) onText,
  required void Function() onEnd,
  required void Function(String code) onError,
}) {
  final ctor = _ctor();
  if (ctor == null) return null;
  final rec = ctor.callAsConstructor<JSObject>();
  rec['lang'] = lang.toJS;
  rec['interimResults'] = true.toJS;
  rec['continuous'] = true.toJS;
  rec['onresult'] = ((JSObject e) {
    final results = e['results'] as JSObject;
    final n = (results['length'] as JSNumber).toDartInt;
    final buf = StringBuffer();
    var allFinal = true;
    for (var i = 0; i < n; i++) {
      final r = results.callMethod<JSObject>('item'.toJS, i.toJS);
      final alt = r.callMethod<JSObject>('item'.toJS, 0.toJS);
      buf.write((alt['transcript'] as JSString).toDart);
      allFinal = allFinal && (r['isFinal'] as JSBoolean).toDart;
    }
    onText(buf.toString().trim(), allFinal);
  }).toJS;
  rec['onerror'] = ((JSObject e) => onError(
    (e['error'] as JSString?)?.toDart ?? 'error',
  )).toJS;
  rec['onend'] = ((JSObject _) => onEnd()).toJS;
  rec.callMethod('start'.toJS);
  return _WebDictation(rec);
}
