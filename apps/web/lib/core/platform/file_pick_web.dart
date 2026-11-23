import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// A file the merchant picked (bytes stay in memory until uploaded).
class PickedFile {
  const PickedFile(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

/// Opens the browser file dialog for photos and Excel/CSV/text/PDF catalogs.
Future<List<PickedFile>> pickFiles() async {
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..multiple = true
    ..accept =
        'image/jpeg,image/png,image/webp,.xlsx,.csv,.txt,text/csv,text/plain,application/pdf';
  final picked = Completer<List<PickedFile>>();
  input.onchange = ((web.Event _) {
    _read(input).then((files) {
      if (!picked.isCompleted) picked.complete(files);
    });
  }).toJS;
  input.oncancel = ((web.Event _) {
    if (!picked.isCompleted) picked.complete(const []);
  }).toJS;
  input.click();
  return picked.future;
}

Future<List<PickedFile>> _read(web.HTMLInputElement input) async {
  final files = input.files;
  final out = <PickedFile>[];
  if (files == null) return out;
  for (var i = 0; i < files.length; i++) {
    final f = files.item(i)!;
    final buf = await f.arrayBuffer().toDart;
    out.add(PickedFile(f.name, buf.toDart.asUint8List()));
  }
  return out;
}
