import 'dart:typed_data';

/// Sample rate the app records at: speech-grade, small uploads (32 KB/s).
const voiceSampleRate = 16000;

/// Wraps raw 16-bit mono PCM in a WAV container the API (and any player) reads.
Uint8List wavFromPcm16(Uint8List pcm, {int sampleRate = voiceSampleRate}) {
  final header = ByteData(44);
  void ascii(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      header.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  header.setUint32(4, 36 + pcm.length, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little); // PCM
  header.setUint16(22, 1, Endian.little); // mono
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, sampleRate * 2, Endian.little);
  header.setUint16(32, 2, Endian.little);
  header.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  header.setUint32(40, pcm.length, Endian.little);
  return Uint8List.fromList([...header.buffer.asUint8List(), ...pcm]);
}

/// Duration of 16-bit mono PCM bytes.
Duration pcmDuration(int bytes, {int sampleRate = voiceSampleRate}) =>
    Duration(microseconds: bytes ~/ 2 * 1000000 ~/ sampleRate);
