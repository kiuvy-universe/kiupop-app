// prefers-reduced-motion: the browser setting on web, MediaQuery elsewhere.
export 'reduced_motion_stub.dart'
    if (dart.library.js_interop) 'reduced_motion_web.dart';
