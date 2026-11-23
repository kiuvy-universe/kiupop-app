// Multi-file picker (photos, Excel, CSV, text, PDF). Web uses a native
// <input type=file>; Android/iOS the system picker.
export 'file_pick_stub.dart'
    if (dart.library.js_interop) 'file_pick_web.dart'
    if (dart.library.io) 'file_pick_io.dart';
