import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:record/record.dart';

import 'wav.dart';

/// Microphone capture as raw 16-bit mono PCM (Android and Web alike).
abstract class VoiceRecorder {
  Future<bool> hasPermission();
  Future<Stream<Uint8List>> start();
  Future<void> stop();

  /// Input level 0..1 while recording (for the live meter).
  Stream<double> level();
  Future<void> dispose();
}

/// Plays back the recording before it is sent.
abstract class AudioPreview {
  Future<void> play(Uint8List wav);
  Future<void> stop();
  Stream<bool> get playing;
  Future<void> dispose();
}

/// Creates fresh recorder/player pairs (one per voice note).
class VoiceIO {
  const VoiceIO({required this.recorder, required this.preview});
  final VoiceRecorder Function() recorder;
  final AudioPreview Function() preview;

  factory VoiceIO.live() => const VoiceIO(
    recorder: RecordVoiceRecorder.new,
    preview: PlayersAudioPreview.new,
  );
}

class RecordVoiceRecorder implements VoiceRecorder {
  final _rec = AudioRecorder();

  @override
  Future<bool> hasPermission() => _rec.hasPermission();

  @override
  Future<Stream<Uint8List>> start() => _rec.startStream(
    const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: voiceSampleRate,
      numChannels: 1,
      noiseSuppress: true,
    ),
  );

  @override
  Future<void> stop() async {
    await _rec.stop();
  }

  @override
  Stream<double> level() => _rec
      .onAmplitudeChanged(const Duration(milliseconds: 120))
      .map((a) => ((a.current + 50) / 50).clamp(0.0, 1.0));

  @override
  Future<void> dispose() => _rec.dispose();
}

class PlayersAudioPreview implements AudioPreview {
  final _player = AudioPlayer();

  @override
  Future<void> play(Uint8List wav) =>
      _player.play(BytesSource(wav, mimeType: 'audio/wav'));

  @override
  Future<void> stop() => _player.stop();

  @override
  Stream<bool> get playing =>
      _player.onPlayerStateChanged.map((s) => s == PlayerState.playing);

  @override
  Future<void> dispose() => _player.dispose();
}
