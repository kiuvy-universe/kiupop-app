import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../app_services.dart';
import '../../../core/motion/reduced_motion.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/kpop_components.dart';
import '../../../l10n/app_localizations.dart';
import '../../agent/presentation/kiu_bubble.dart';
import '../data/speech_api.dart';
import '../data/voice_io.dart';
import '../data/wav.dart';

/// Shows the "Hablar con Kiu" sheet. Resolves to the text the merchant
/// confirmed, or null if they closed it or chose to type instead.
Future<String?> showVoiceNoteSheet(
  BuildContext context, {
  required AppServices services,
  required SpeechStatus status,
  String? sessionId,
}) => KPopSheet.show<String>(
  context: context,
  builder: (_) =>
      VoiceNoteSheet(services: services, status: status, sessionId: sessionId),
);

enum VoiceStage { idle, recording, recorded, transcribing, review, error }

class VoiceNoteSheet extends StatefulWidget {
  const VoiceNoteSheet({
    super.key,
    required this.services,
    required this.status,
    this.sessionId,
  });

  final AppServices services;
  final SpeechStatus status;
  final String? sessionId;

  @override
  State<VoiceNoteSheet> createState() => _VoiceNoteSheetState();
}

class _VoiceNoteSheetState extends State<VoiceNoteSheet> {
  VoiceStage _stage = VoiceStage.idle;
  VoiceRecorder? _recorder;
  late final AudioPreview _preview = widget.services.voice.preview();
  final _pcm = BytesBuilder(copy: false);
  StreamSubscription<Uint8List>? _audioSub;
  Completer<void>? _streamDone;
  StreamSubscription<double>? _levelSub;
  StreamSubscription<bool>? _playSub;
  Timer? _ticker;
  Duration _elapsed = Duration.zero;
  double _level = 0;
  bool _playing = false;
  Uint8List? _wav;
  String? _error;
  Transcript? _transcript;
  final _text = TextEditingController();

  Duration get _max => Duration(seconds: widget.status.maxSeconds);

  @override
  void initState() {
    super.initState();
    _playSub = _preview.playing.listen((p) {
      if (mounted) setState(() => _playing = p);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _audioSub?.cancel();
    _levelSub?.cancel();
    _playSub?.cancel();
    unawaited(_recorder?.dispose());
    unawaited(_preview.dispose());
    _text.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final l10n = AppLocalizations.of(context);
    await _preview.stop();
    final rec = _recorder ??= widget.services.voice.recorder();
    try {
      if (!await rec.hasPermission()) {
        return _fail(l10n.voicePermissionDenied);
      }
      _pcm.clear();
      final stream = await rec.start();
      final done = _streamDone = Completer<void>();
      _audioSub = stream.listen(
        _pcm.add,
        onDone: () => done.isCompleted ? null : done.complete(),
        onError: (Object _) => done.isCompleted ? null : done.complete(),
      );
      _levelSub = rec.level().listen((v) {
        if (mounted) setState(() => _level = v);
      });
    } on Object {
      return _fail(l10n.voiceMicError);
    }
    if (!mounted) return;
    setState(() {
      _stage = VoiceStage.recording;
      _elapsed = Duration.zero;
      _wav = null;
      _error = null;
    });
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;
      setState(() => _elapsed = pcmDuration(_pcm.length));
      if (_elapsed >= _max) unawaited(_stop());
    });
  }

  Future<void> _stop() async {
    _ticker?.cancel();
    unawaited(_levelSub?.cancel());
    // Stopping flushes the last PCM chunks; the stream's end says when.
    unawaited(_recorder?.stop().catchError((Object _) {}));
    await (_streamDone?.future ?? Future<void>.value()).timeout(
      const Duration(seconds: 2),
      onTimeout: () {},
    );
    unawaited(_audioSub?.cancel());
    if (!mounted) return;
    final pcm = _pcm.toBytes();
    final dur = pcmDuration(pcm.length);
    if (dur < const Duration(milliseconds: 800)) {
      return _fail(AppLocalizations.of(context).voiceTooShort);
    }
    setState(() {
      _wav = wavFromPcm16(pcm);
      _elapsed = dur;
      _stage = VoiceStage.recorded;
      _level = 0;
    });
    widget.services.funnel.record(
      'audio_recorded',
      sessionId: widget.sessionId,
      meta: {'duration_ms': dur.inMilliseconds},
    );
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _stage = VoiceStage.error;
      _error = message;
      _level = 0;
    });
  }

  Future<void> _discard() async {
    _ticker?.cancel();
    await _preview.stop();
    if (_stage == VoiceStage.recording) {
      unawaited(_levelSub?.cancel());
      unawaited(_recorder?.stop().catchError((Object _) {}));
      unawaited(_audioSub?.cancel());
    }
    if (!mounted) return;
    setState(() {
      _stage = VoiceStage.idle;
      _wav = null;
      _elapsed = Duration.zero;
      _transcript = null;
      _text.clear();
    });
  }

  Future<void> _transcribe() async {
    final wav = _wav;
    if (wav == null) return;
    await _preview.stop();
    setState(() => _stage = VoiceStage.transcribing);
    final res = await widget.services.speech.transcribe(
      wav,
      sessionId: widget.sessionId,
    );
    if (!mounted) return;
    switch (res) {
      case ApiSuccess(:final value):
        _text.text = value.text;
        setState(() {
          _transcript = value;
          _stage = VoiceStage.review;
        });
      case final ApiFailure<Transcript> f:
        _fail(failureMessage(context, f));
    }
  }

  void _send() {
    final text = _text.text.trim();
    if (text.isEmpty) {
      setState(
        () => _error = AppLocalizations.of(context).voiceEmptyTranscript,
      );
      return;
    }
    Navigator.of(context).pop(text);
  }

  String _clock(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final mood = switch (_stage) {
      VoiceStage.recording => KiuMood.listening,
      VoiceStage.transcribing => KiuMood.thinking,
      VoiceStage.review => KiuMood.success,
      VoiceStage.error => KiuMood.error,
      _ => KiuMood.idle,
    };
    return SafeArea(
      child: SingleChildScrollView(
        key: const Key('voice-sheet'),
        padding: EdgeInsets.fromLTRB(
          KPopSpace.gutter,
          0,
          KPopSpace.gutter,
          KPopSpace.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                KiuBubbleAnimation(size: 64, mood: mood),
                const SizedBox(width: KPopSpace.sm),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      l10n.voiceTitle,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: l10n.close,
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: KPopSpace.sm),
            ..._body(context, l10n, theme),
          ],
        ),
      ),
    );
  }

  List<Widget> _body(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
  ) {
    final scheme = theme.colorScheme;
    final writeInstead = KPopButton(
      key: const Key('voice-write-instead'),
      tone: KPopButtonTone.text,
      label: l10n.voiceWriteInstead,
      expand: true,
      onPressed: () => Navigator.of(context).pop(),
    );
    switch (_stage) {
      case VoiceStage.idle:
        return [
          Text(
            l10n.voiceIdleHint(widget.status.maxSeconds),
            style: theme.textTheme.bodyLarge?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: KPopSpace.lg),
          Center(
            child: _MicButton(
              key: const Key('voice-record'),
              tooltip: l10n.voiceStart,
              icon: Icons.mic_rounded,
              onPressed: _start,
            ),
          ),
          const SizedBox(height: KPopSpace.xs),
          Center(
            child: Text(
              l10n.voiceTapToRecord,
              style: theme.textTheme.labelLarge,
            ),
          ),
          const SizedBox(height: KPopSpace.md),
          writeInstead,
        ];
      case VoiceStage.recording:
        return [
          Semantics(
            liveRegion: true,
            child: Text(
              '${l10n.voiceRecording} ${_clock(_elapsed)} / ${_clock(_max)}',
              key: const Key('voice-clock'),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: KPopSpace.sm),
          _LevelMeter(level: _level),
          const SizedBox(height: KPopSpace.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(KPopRadius.chip),
            child: LinearProgressIndicator(
              value: _elapsed.inMilliseconds / _max.inMilliseconds,
              minHeight: 6,
            ),
          ),
          const SizedBox(height: KPopSpace.lg),
          Center(
            child: _MicButton(
              key: const Key('voice-stop'),
              tooltip: l10n.voiceStop,
              icon: Icons.stop_rounded,
              recording: true,
              onPressed: _stop,
            ),
          ),
          const SizedBox(height: KPopSpace.md),
          KPopButton(
            key: const Key('voice-discard'),
            tone: KPopButtonTone.text,
            label: l10n.voiceDiscard,
            expand: true,
            onPressed: _discard,
          ),
        ];
      case VoiceStage.recorded:
        return [
          KPopSurface(
            flat: true,
            color: KPopTint.lavender.background(scheme),
            padding: const EdgeInsets.all(KPopSpace.sm),
            child: Row(
              children: [
                IconButton.filledTonal(
                  key: const Key('voice-play'),
                  tooltip: _playing ? l10n.voicePause : l10n.voicePlay,
                  onPressed: () =>
                      _playing ? _preview.stop() : _preview.play(_wav!),
                  icon: Icon(
                    _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  ),
                ),
                const SizedBox(width: KPopSpace.sm),
                Expanded(
                  child: Text(
                    '${l10n.voiceNote} · ${_clock(_elapsed)}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: KPopTint.lavender.foreground(scheme),
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('voice-delete'),
                  tooltip: l10n.voiceDelete,
                  onPressed: _discard,
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ),
          ),
          const SizedBox(height: KPopSpace.lg),
          KPopButton(
            key: const Key('voice-transcribe'),
            icon: Icons.auto_awesome_rounded,
            label: l10n.voiceTranscribe,
            expand: true,
            onPressed: _transcribe,
          ),
          const SizedBox(height: KPopSpace.xs),
          KPopButton(
            key: const Key('voice-rerecord'),
            tone: KPopButtonTone.outlined,
            icon: Icons.replay_rounded,
            label: l10n.voiceRerecord,
            expand: true,
            onPressed: _start,
          ),
        ];
      case VoiceStage.transcribing:
        return [
          const SizedBox(height: KPopSpace.md),
          Semantics(
            liveRegion: true,
            child: Text(
              l10n.voiceTranscribing,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: KPopSpace.md),
          const Center(child: CircularProgressIndicator()),
          const SizedBox(height: KPopSpace.lg),
        ];
      case VoiceStage.review:
        return [
          Text(l10n.voiceReviewTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: KPopSpace.xxs),
          Text(
            l10n.voiceReviewHint,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: KPopSpace.sm),
          TextField(
            key: const Key('voice-transcript'),
            controller: _text,
            minLines: 3,
            maxLines: 8,
            maxLength: 1000,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: l10n.voiceTranscriptLabel,
              errorText: _error,
            ),
          ),
          if (_transcript != null)
            Text(
              l10n.voiceProvider(_providerName(_transcript!.provider)),
              key: const Key('voice-provider'),
              style: theme.textTheme.bodySmall,
            ),
          const SizedBox(height: KPopSpace.md),
          KPopButton(
            key: const Key('voice-send'),
            icon: Icons.arrow_upward_rounded,
            label: l10n.voiceSend,
            expand: true,
            onPressed: _send,
          ),
          const SizedBox(height: KPopSpace.xs),
          KPopButton(
            tone: KPopButtonTone.outlined,
            icon: Icons.replay_rounded,
            label: l10n.voiceRerecord,
            expand: true,
            onPressed: _discard,
          ),
        ];
      case VoiceStage.error:
        return [
          KPopBanner(
            key: const Key('voice-error'),
            text: _error ?? l10n.voiceMicError,
            icon: Icons.mic_off_rounded,
            tint: KPopTint.bubblegum,
          ),
          const SizedBox(height: KPopSpace.md),
          KPopButton(
            label: l10n.retry,
            icon: Icons.replay_rounded,
            expand: true,
            onPressed: _wav != null ? _transcribe : _discard,
          ),
          const SizedBox(height: KPopSpace.xs),
          writeInstead,
        ];
    }
  }

  static String _providerName(String id) => switch (id) {
    'google-stt-v1' => 'Google Speech-to-Text',
    'dev-echo' => 'una prueba local sin transcripción',
    _ => id,
  };
}

class _MicButton extends StatelessWidget {
  const _MicButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.recording = false,
  });
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool recording;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = recording
        ? KPopTint.bubblegum.background(scheme)
        : scheme.primary;
    final fg = recording
        ? KPopTint.bubblegum.foreground(scheme)
        : scheme.onPrimary;
    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: bg,
          shape: const CircleBorder(),
          elevation: 0,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox.square(
              dimension: 88,
              child: Icon(icon, size: 40, color: fg),
            ),
          ),
        ),
      ),
    );
  }
}

/// Five soft bars that follow the input level (static with reduced motion).
class _LevelMeter extends StatelessWidget {
  const _LevelMeter({required this.level});
  final double level;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reduced =
        MediaQuery.disableAnimationsOf(context) || systemPrefersReducedMotion();
    final v = reduced ? .5 : level;
    return ExcludeSemantics(
      child: SizedBox(
        height: 40,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (final w in const [.45, .75, 1.0, .75, .45])
              AnimatedContainer(
                duration: reduced ? Duration.zero : KPopMotion.fast,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: 10,
                height: 8 + 32 * (v * w).clamp(0.0, 1.0),
                decoration: BoxDecoration(
                  color: KPopTint.bubblegum
                      .foreground(scheme)
                      .withValues(alpha: .7),
                  borderRadius: BorderRadius.circular(KPopRadius.chip),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
