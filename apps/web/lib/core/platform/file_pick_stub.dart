import 'dart:typed_data';

/// A file the merchant picked (bytes stay in memory until uploaded).
class PickedFile {
  const PickedFile(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

/// No native picker outside the browser.
Future<List<PickedFile>> pickFiles() async => const [];
