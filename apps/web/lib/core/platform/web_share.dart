// Native share sheet: Web Share API in the browser, share_plus on Android/iOS.
export 'web_share_stub.dart'
    if (dart.library.js_interop) 'web_share_web.dart'
    if (dart.library.io) 'web_share_io.dart';
