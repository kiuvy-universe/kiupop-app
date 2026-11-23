import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Opens the OS share sheet (WhatsApp, Facebook, …). Returns false if unsupported or dismissed.
Future<bool> nativeShare(String title, String text, String url) async {
  final data = web.ShareData(title: title, text: text, url: url);
  try {
    if (!web.window.navigator.canShare(data)) return false;
    await web.window.navigator.share(data).toDart;
    return true;
  } on Object {
    return false;
  }
}
