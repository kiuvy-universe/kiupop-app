import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// A file the merchant picked (bytes stay in memory until uploaded).
class PickedFile {
  const PickedFile(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

/// Android/iOS system picker for photos and Excel/CSV/text/PDF catalogs.
Future<List<PickedFile>> pickFiles() async {
  final files = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: const [
      'jpg',
      'jpeg',
      'png',
      'webp',
      'xlsx',
      'csv',
      'txt',
      'pdf',
    ],
  );
  return [for (final f in files) PickedFile(f.name, await f.readAsBytes())];
}
