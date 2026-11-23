import 'package:share_plus/share_plus.dart';

/// Android/iOS share sheet (WhatsApp, Facebook, …). False if unavailable.
Future<bool> nativeShare(String title, String text, String url) async {
  try {
    final r = await SharePlus.instance.share(
      ShareParams(title: title, subject: title, text: '$text\n$url'.trim()),
    );
    return r.status != ShareResultStatus.unavailable;
  } on Object {
    return false;
  }
}
