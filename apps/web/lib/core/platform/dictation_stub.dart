/// A running dictation.
abstract class Dictation {
  void stop();
}

/// Whether this platform can transcribe speech.
bool dictationAvailable() => false;

/// Starts dictation; returns null when unavailable.
Dictation? startDictation({
  required String lang,
  required void Function(String text, bool isFinal) onText,
  required void Function() onEnd,
  required void Function(String code) onError,
}) => null;
