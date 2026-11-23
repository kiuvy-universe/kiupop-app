// Voice → text for the composer. Web: the browser's speech recognition;
// Android/iOS: the system recognizer. KiuPop stores no audio; the merchant
// reviews the text before sending.
export 'dictation_stub.dart'
    if (dart.library.js_interop) 'dictation_web.dart'
    if (dart.library.io) 'dictation_io.dart';
