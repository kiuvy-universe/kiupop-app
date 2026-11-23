// Tiny key-value persistence: browser localStorage on web, SharedPreferences
// on Android/iOS, memory elsewhere.
export 'local_store_stub.dart'
    if (dart.library.js_interop) 'local_store_web.dart'
    if (dart.library.io) 'local_store_io.dart';
