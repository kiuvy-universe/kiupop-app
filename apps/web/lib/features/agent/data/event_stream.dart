// Opens a Server-Sent Events stream when the platform supports it (web).
// Returns null elsewhere so callers fall back to long-polling.
export 'event_stream_stub.dart'
    if (dart.library.js_interop) 'event_stream_web.dart';
