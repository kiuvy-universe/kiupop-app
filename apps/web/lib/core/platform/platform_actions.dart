import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart' hide PickedFile;
import 'package:url_launcher/url_launcher.dart';

import 'dictation.dart' as voice;
import 'file_pick.dart' as files;

export 'dictation.dart' show Dictation;
import 'web_share.dart';

export 'file_pick.dart' show PickedFile;

/// A picked image ready to upload.
class PickedImage {
  const PickedImage(this.bytes, this.filename);
  final Uint8List bytes;
  final String filename;
}

/// Side effects the UI needs, injectable so widget tests never open real URLs.
class PlatformActions {
  const PlatformActions({
    required this.openUrl,
    required this.copyText,
    required this.pickImage,
    Future<bool> Function(String title, String text, String url)? share,
    Future<List<files.PickedFile>> Function()? pickFiles,
    bool Function()? dictationAvailable,
    voice.Dictation? Function({
      required String lang,
      required void Function(String text, bool isFinal) onText,
      required void Function() onEnd,
      required void Function(String code) onError,
    })?
    startDictation,
  }) : dictationAvailable = dictationAvailable ?? _noVoice,
       startDictation = startDictation ?? _noDictation,
       share = share ?? _noShare,
       pickFiles = pickFiles ?? _noFiles;

  static Future<List<files.PickedFile>> _noFiles() async => const [];
  static bool _noVoice() => false;
  static voice.Dictation? _noDictation({
    required String lang,
    required void Function(String text, bool isFinal) onText,
    required void Function() onEnd,
    required void Function(String code) onError,
  }) => null;

  static Future<bool> _noShare(String title, String text, String url) async =>
      false;

  /// Real implementations (browser tab, clipboard, file picker).
  factory PlatformActions.live() => PlatformActions(
    openUrl: (uri) => launchUrl(
      uri,
      webOnlyWindowName: '_blank',
      mode: LaunchMode.externalApplication,
    ),
    copyText: (text) => Clipboard.setData(ClipboardData(text: text)),
    share: nativeShare,
    pickFiles: files.pickFiles,
    dictationAvailable: voice.dictationAvailable,
    startDictation: voice.startDictation,
    pickImage: () async {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (file == null) return null;
      return PickedImage(await file.readAsBytes(), file.name);
    },
  );

  final Future<bool> Function(Uri uri) openUrl;
  final Future<void> Function(String text) copyText;
  final Future<PickedImage?> Function() pickImage;

  /// Native share sheet; false means "not available, copy the link instead".
  final Future<bool> Function(String title, String text, String url) share;

  /// Photos and catalogs to share with Kiu.
  final Future<List<files.PickedFile>> Function() pickFiles;

  /// Speech to text for the composer (the merchant edits before sending).
  final bool Function() dictationAvailable;
  final voice.Dictation? Function({
    required String lang,
    required void Function(String text, bool isFinal) onText,
    required void Function() onEnd,
    required void Function(String code) onError,
  })
  startDictation;
}
