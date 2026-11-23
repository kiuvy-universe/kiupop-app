import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app_services.dart';
import '../../../core/network/api_client.dart';
import '../../../core/motion/reduced_motion.dart';
import '../../../core/platform/platform_actions.dart' show Dictation;
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/kpop_components.dart';
import '../../../core/widgets/settings_sheet.dart';
import '../../../core/widgets/theme_toggle.dart';
import '../../../l10n/app_localizations.dart';
import '../../storefront/data/storefront_models.dart';
import '../../storefront/presentation/storefront_renderer.dart';
import '../data/agent_models.dart';
import '../data/kiu_controller.dart';
import 'kiu_bubble.dart';
import '../../voice/data/speech_api.dart';
import '../../voice/presentation/voice_note_sheet.dart';
import 'paywall_sheet.dart';

/// "Contale a Kiu sobre tu negocio" → a few questions → the store builds
/// itself → POP → publish → share.
class KiuBuilderPage extends StatefulWidget {
  const KiuBuilderPage({super.key, required this.services, this.controller});
  final AppServices services;

  /// Injected in tests; built from services otherwise.
  final KiuController? controller;

  @override
  State<KiuBuilderPage> createState() => _KiuBuilderPageState();
}

class _KiuBuilderPageState extends State<KiuBuilderPage> {
  late final KiuController _c =
      widget.controller ?? KiuController(widget.services.agent);
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  bool _popping = false;
  bool _revealed = false;
  String? _sessionId;
  bool _awayFromBottom = false;

  /// Voice notes need a real transcription provider (asked once).
  SpeechStatus _speech = SpeechStatus.off;

  /// The merchant picked "talk" or "write" for their first idea.
  bool _intakeChosen = false;

  /// "Hacer un ajuste": the composer invites a change after the reveal.
  bool _adjusting = false;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onChange);
    _scroll.addListener(_onScroll);
    _c.start();
    widget.services.speech.status().then((r) {
      if (r case ApiSuccess(:final value) when mounted) {
        setState(() => _speech = value);
      }
    });
  }

  void _chooseIntake({required bool audio}) {
    setState(() => _intakeChosen = true);
    widget.services.funnel.record(
      'intake_method_selected',
      sessionId: _c.session?.id,
      meta: {audio ? 'method_audio' : 'method_text': 1},
    );
    if (audio) {
      _openVoice();
    } else {
      _focus.requestFocus();
    }
  }

  /// Voice note → reviewed transcript → Kiu. Falls back to typing.
  Future<void> _openVoice() async {
    if (!_speech.enabled) {
      showSnack(context, AppLocalizations.of(context).voiceUnavailable);
      _focus.requestFocus();
      return;
    }
    final text = await showVoiceNoteSheet(
      context,
      services: widget.services,
      status: _speech,
      sessionId: _c.session?.id,
    );
    if (!mounted) return;
    if (text != null && text.trim().isNotEmpty) {
      await _send(text);
    } else {
      _focus.requestFocus();
    }
  }

  void _adjust() {
    setState(() => _adjusting = true);
    _focus.requestFocus();
  }

  void _shared(String channel) => widget.services.funnel.record(
    'catalog_shared',
    sessionId: _c.session?.id,
    meta: {'channel_$channel': 1},
  );

  /// Shows "go to latest" once the reader has scrolled up past one screen-ish.
  void _onScroll() {
    if (!_scroll.hasClients) return;
    final away = _scroll.offset > 120;
    if (away != _awayFromBottom) setState(() => _awayFromBottom = away);
  }

  void _scrollToLatest() {
    if (!_scroll.hasClients) return;
    if (MediaQuery.disableAnimationsOf(context) ||
        systemPrefersReducedMotion()) {
      _scroll.jumpTo(0);
      return;
    }
    _scroll.animateTo(0, duration: KPopMotion.standard, curve: KPopMotion.ease);
  }

  @override
  void dispose() {
    _c.removeListener(_onChange);
    _scroll.removeListener(_onScroll);
    if (widget.controller == null) _c.dispose();
    _dictation?.stop();
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    final session = _c.session;
    setState(() {
      if (session?.id != _sessionId) {
        _sessionId = session?.id;
        _popping = false;
        _revealed = false;
        if (_scroll.hasClients) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
          });
        }
      }
      if (_c.popRequested) {
        _popping = true;
      } else {
        _revealed = session != null && (session.ready || session.published);
      }
    });
  }

  void _popFinished() {
    if (!_popping) return;
    setState(() {
      _popping = false;
      _revealed = true;
    });
    _c.consumePop();
  }

  Future<void> _send([String? text]) async {
    final t = text ?? _input.text;
    if (t.trim().isEmpty || _c.sending || _c.publishing) return;
    if (text == null) _input.clear();
    _scrollToLatest();
    final ok = await _c.send(t);
    if (!ok && text == null && mounted && _input.text.isEmpty) _input.text = t;
    if (mounted) _focus.requestFocus();
  }

  Dictation? _dictation;
  String _dictationBase = '';

  bool get _listening => _dictation != null;

  void _toggleDictation() {
    final l10n = AppLocalizations.of(context);
    if (_dictation != null) {
      _dictation!.stop();
      setState(() => _dictation = null);
      return;
    }
    _dictationBase = _input.text.trim();
    final d = widget.services.platform.startDictation(
      lang: 'es-CR',
      onText: (text, _) {
        if (!mounted) return;
        // Shown in the input so the merchant can correct it before sending.
        _input.text = [
          _dictationBase,
          text,
        ].where((t) => t.isNotEmpty).join(' ');
      },
      onEnd: () {
        if (mounted) setState(() => _dictation = null);
      },
      onError: (code) {
        if (!mounted) return;
        setState(() => _dictation = null);
        showSnack(
          context,
          code == 'not-allowed' ? l10n.micDenied : l10n.micError,
        );
      },
    );
    setState(() => _dictation = d);
  }

  Future<void> _attach() async {
    final l10n = AppLocalizations.of(context);
    final files = await widget.services.platform.pickFiles();
    if (!mounted || files.isEmpty) return;
    await _c.upload(
      files,
      tooMany: l10n.fileTooMany,
      tooBig: l10n.fileTooBig,
      tooManyBytes: l10n.fileTooManyTotal,
    );
  }

  Future<void> _quick(QuickReply r) async {
    if (r.isPublish) return _confirmPublish();
    await _send(r.value);
  }

  Future<void> _confirmPublish({bool retried = false}) async {
    final session = _c.session;
    if (session?.ready != true || _c.publishing || _c.paying) return;
    final l10n = AppLocalizations.of(context);
    if (session!.needsPlan) {
      // Quiz funnel: the store was free to see; publishing goes through the
      // paywall. Paying (test mode) is the explicit confirmation to publish.
      widget.services.funnel.record('paywall_viewed', sessionId: session.id);
      final paid = await PaywallSheet.show(
        context,
        paywall: session.paywall,
        pay: _c.activatePlan,
      );
      if (!paid || !mounted) return;
      showSnack(context, l10n.paywallActivated);
      return _publishNow(retried: retried);
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: Text(l10n.publishConfirmTitle),
        content: Text(l10n.publishConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const Key('publish-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.publishConfirmCta),
          ),
        ],
      ),
    );
    if (ok != true || !mounted || _c.session?.ready != true || _c.publishing) {
      return;
    }
    await _publishNow(retried: retried);
  }

  Future<void> _publishNow({required bool retried}) async {
    final l10n = AppLocalizations.of(context);
    final res = await _c.publish();
    if (!mounted) return;
    if (res case ApiFailure(:final code, :final message)) {
      // The server is the authority: a stale screen gets the paywall once.
      if (code == 'plan_required' &&
          !retried &&
          _c.session?.needsPlan == true) {
        return _confirmPublish(retried: true);
      }
      showSnack(context, message ?? l10n.publishFailed);
    }
  }

  void _openPreview() {
    final view = _c.preview;
    if (view == null) return;
    widget.services.funnel.record(
      'store_preview_opened',
      sessionId: _c.session?.id,
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) => KPopScaffold(
          appBar: AppBar(title: Text(AppLocalizations.of(ctx).previewTitle)),
          body: ListenableBuilder(
            listenable: _c,
            builder: (ctx, _) => StorefrontRenderer(
              view: _c.preview ?? view,
              imageUri: widget.services.storefront.imageUri,
            ),
          ),
          bottomNavigationBar: ListenableBuilder(
            listenable: _c,
            builder: (ctx, _) {
              final session = _c.session;
              if (session == null || !session.ready || session.published) {
                return const SizedBox.shrink();
              }
              return SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _confirmPublish();
                    },
                    icon: const Icon(Icons.rocket_launch_outlined),
                    label: Text(AppLocalizations.of(ctx).publishCta),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  KiuMood _mood(AgentSession s) {
    if (s.status == 'failed' ||
        _c.sendError != null ||
        _c.readinessFailure != null) {
      return KiuMood.error;
    }
    if (s.published) return KiuMood.success;
    // Kiu celebrates only once the POP started or the store was already
    // revealed; until then it waits calmly.
    if (s.ready) return _popping || _revealed ? KiuMood.success : KiuMood.idle;
    if (_listening) return KiuMood.listening;
    if (_c.sending || _c.uploading > 0) return KiuMood.thinking;
    if (s.status == 'building' && s.pending == null) return KiuMood.processing;
    // Waiting for the merchant: one breath, then still (no endless loop).
    return KiuMood.idle;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final s = _c.session;
    final f = _c.loadFailure;
    if (f != null) {
      return KPopScaffold(
        appBar: AppBar(
          title: const KiuPopLogo(size: 36),
          actions: [ThemeToggle(controller: widget.services.theme)],
        ),
        body: MessageState(
          icon: Icons.cloud_off_rounded,
          title: l10n.kiuLoadError,
          body: failureMessage(context, f),
          actionLabel: l10n.retry,
          onAction: _c.start,
        ),
      );
    }
    if (s == null) {
      return KPopScaffold(
        appBar: AppBar(title: const KiuPopLogo(size: 36)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return KPopScaffold(
      appBar: AppBar(
        title: const KiuPopLogo(size: 32),
        actions: [
          KPopSettingsButton(
            theme: widget.services.theme,
            aiMode: s.aiMode,
            onSignOut: () async {
              await widget.services.auth.signOut();
              if (mounted) this.context.go('/');
            },
          ),
          const SizedBox(width: KPopSpace.xxs),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, bounds) {
          final wide = bounds.maxWidth >= 1000;
          // Large text needs the room the stage would take: with it, the
          // stage joins the message list (like with the keyboard open).
          final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
          // While typing on a phone the conversation gets the room too.
          final typing = MediaQuery.viewInsetsOf(context).bottom > 0;
          final short =
              bounds.maxHeight < 400 * textScale.clamp(1.0, 2.0) ||
              (typing && !wide && bounds.maxHeight < 560);
          if (short &&
              _popping &&
              (_awayFromBottom || bounds.maxHeight < 112)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _popFinished();
            });
          }
          final chat = _ChatPanel(
            state: this,
            session: s,
            short: short,
            height: bounds.maxHeight,
            stage: _Stage(
              state: this,
              session: s,
              compact: !wide,
              short: short,
            ),
          );
          if (!wide) return PageBody(maxWidth: 740, child: chat);
          return PageBody(
            maxWidth: 1536,
            child: Padding(
              padding: const EdgeInsets.only(bottom: KPopSpace.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: bounds.maxWidth >= 1280 ? 476 : 424,
                    child: chat,
                  ),
                  const SizedBox(width: KPopSpace.md),
                  Expanded(
                    child: KPopSurface(
                      padding: EdgeInsets.zero,
                      raised: true,
                      child: _PreviewPanel(state: this, session: s),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Kiu's stage: a ceramic card where Kiu shows what the backend confirmed
/// (listening, building with real progress, POP, ready). After the POP, on
/// phones, the finished store peeks in with the action to open it.
class _Stage extends StatelessWidget {
  const _Stage({
    required this.state,
    required this.session,
    required this.compact,
    required this.short,
  });
  final _KiuBuilderPageState state;
  final AgentSession session;
  final bool compact, short;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = state._c;
    final pct = session.percent.clamp(0, 100);
    final mood = state._mood(session);
    final failure = c.readinessFailure;
    final status = failure != null
        ? failureMessage(context, failure)
        : session.published
        ? l10n.stagePublished
        : session.ready
        ? (state._revealed && !state._popping
              ? l10n.revealTitle
              : l10n.stageReady)
        : mood == KiuMood.thinking
        ? l10n.kiuThinking
        : mood == KiuMood.error
        ? ((c.sendError?.isNotEmpty ?? false)
              ? c.sendError!
              : l10n.errorGeneric)
        : mood == KiuMood.processing
        ? l10n.stageBuilding(pct)
        : l10n.stageListening;
    final bigText = MediaQuery.textScalerOf(context).scale(16) > 21;
    final hint = short || bigText || failure != null || mood == KiuMood.error
        ? null
        : session.published
        ? l10n.stagePublishedHint
        : session.ready
        ? (state._popping ? null : l10n.revealBody)
        : mood == KiuMood.processing
        ? l10n.stageBuildingHint
        : !session.started
        ? l10n.stageListeningHint
        : null;
    final fg = KPopTint.lavender.foreground(scheme);
    final peek =
        !state._popping &&
        compact &&
        !short &&
        state._revealed &&
        session.ready &&
        !session.published &&
        c.preview != null &&
        MediaQuery.sizeOf(context).width >= 340;
    final radius = short ? KPopRadius.tile : KPopRadius.card;
    final revealed =
        !state._popping &&
        state._revealed &&
        session.ready &&
        !session.published;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            KPopTint.lavender.background(scheme),
            if (scheme.brightness == Brightness.dark)
              scheme.surfaceContainerHigh
            else
              Color.lerp(
                KPopTint.lavender.background(scheme),
                KPopTint.peach.background(scheme),
                .55,
              )!,
          ],
        ),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: KPopElevation.soft(scheme.brightness),
      ),
      child: Padding(
        padding: EdgeInsets.all(short ? KPopSpace.xs : KPopSpace.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (short && !state._popping)
                  const KiuAvatar(size: 36)
                else
                  KiuBubbleAnimation(
                    key: ValueKey('kiu-motion-${session.id}'),
                    progress: pct / 100,
                    mood: mood,
                    pop: state._popping,
                    onPopped: state._popFinished,
                    size: short
                        ? 52
                        : compact
                        ? 96
                        : 124,
                  ),
                const SizedBox(width: KPopSpace.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        liveRegion: true,
                        child: Text(
                          status,
                          key: const Key('stage-status'),
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: fg,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (hint != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          hint,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: fg.withValues(alpha: .86),
                          ),
                        ),
                      ],
                      if (!short &&
                          (mood == KiuMood.processing || state._popping)) ...[
                        const SizedBox(height: KPopSpace.xs),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(KPopRadius.chip),
                          child: LinearProgressIndicator(
                            value: pct / 100,
                            minHeight: 8,
                            color: scheme.tertiary,
                            backgroundColor: scheme.surface.withValues(
                              alpha: .7,
                            ),
                          ),
                        ),
                      ],
                      if (failure != null)
                        TextButton(
                          onPressed: c.retryReadiness,
                          child: Text(l10n.retry),
                        ),
                      if (state._popping)
                        TextButton(
                          key: const Key('skip-pop'),
                          onPressed: state._popFinished,
                          child: Text(
                            l10n.skipAnimation,
                            textAlign: TextAlign.start,
                          ),
                        ),
                      if (revealed &&
                          c.preview == null &&
                          c.previewFailure != null)
                        TextButton(
                          onPressed: c.loadPreview,
                          child: Text(l10n.retry),
                        ),
                    ],
                  ),
                ),
                if (peek) ...[
                  const SizedBox(width: KPopSpace.xs),
                  _StorePeek(state: state),
                ],
              ],
            ),
            if (revealed && !short && (c.preview != null || !compact))
              Padding(
                padding: const EdgeInsets.only(top: KPopSpace.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (compact && c.preview != null) ...[
                      KPopButton(
                        key: const Key('open-preview'),
                        onPressed: state._openPreview,
                        icon: Icons.visibility_outlined,
                        label: l10n.revealExplore,
                        expand: true,
                      ),
                      const SizedBox(height: KPopSpace.xs),
                    ],
                    Wrap(
                      spacing: KPopSpace.xs,
                      runSpacing: KPopSpace.xs,
                      alignment: WrapAlignment.center,
                      children: [
                        KPopButton(
                          key: const Key('adjust-store'),
                          tone: KPopButtonTone.outlined,
                          onPressed: state._adjust,
                          label: l10n.revealAdjust,
                        ),
                        KPopButton(
                          key: const Key('continue-publish'),
                          tone: KPopButtonTone.tonal,
                          onPressed: c.publishing
                              ? null
                              : state._confirmPublish,
                          label: l10n.revealContinue,
                        ),
                      ],
                    ),
                  ],
                ),
              )
            else if (revealed && short && compact && c.preview != null)
              Padding(
                padding: const EdgeInsets.only(top: KPopSpace.xs),
                child: KPopButton(
                  key: const Key('open-preview'),
                  onPressed: state._openPreview,
                  icon: Icons.visibility_outlined,
                  label: l10n.revealExplore,
                  expand: true,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A small live thumbnail of the finished store that rises in after the POP
/// (instant with reduced motion). Tapping it opens the full preview.
class _StorePeek extends StatelessWidget {
  const _StorePeek({required this.state});
  final _KiuBuilderPageState state;

  @override
  Widget build(BuildContext context) {
    final view = state._c.preview!;
    final scheme = Theme.of(context).colorScheme;
    final reduced =
        MediaQuery.disableAnimationsOf(context) || systemPrefersReducedMotion();
    final thumb = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(KPopRadius.control),
        border: Border.all(color: scheme.surface, width: 3),
        boxShadow: KPopElevation.raised(scheme.brightness),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(KPopRadius.control - 3),
        child: SizedBox(
          width: 68,
          height: 112,
          child: ExcludeSemantics(
            child: ExcludeFocus(
              child: IgnorePointer(
                child: FittedBox(
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: 390,
                    height: 640,
                    child: StorefrontRenderer(
                      view: view,
                      imageUri: state.widget.services.storefront.imageUri,
                      bottomPadding: 0,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: reduced ? 1 : 0, end: 1),
      duration: reduced ? Duration.zero : KPopMotion.slow,
      curve: KPopMotion.ease,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 18 * (1 - t)),
          child: Transform.scale(scale: .9 + .1 * t, child: child),
        ),
      ),
      // The labelled «Ver vista previa» button carries the same action.
      child: ExcludeSemantics(
        child: GestureDetector(
          key: const Key('store-peek'),
          onTap: state._openPreview,
          child: thumb,
        ),
      ),
    );
  }
}

class _TaskChip extends StatelessWidget {
  const _TaskChip({required this.task});
  final BuildTask task;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final (icon, tint, hint) = switch (task.status) {
      'done' => (Icons.check_circle_rounded, KPopTint.mint, l10n.taskDone),
      'running' => (Icons.autorenew_rounded, KPopTint.butter, l10n.taskRunning),
      'needs_input' => (
        Icons.chat_bubble_outline_rounded,
        KPopTint.peach,
        l10n.taskNeedsInput,
      ),
      'skipped' => (
        Icons.remove_circle_outline,
        KPopTint.babyBlue,
        l10n.taskSkipped,
      ),
      'failed' => (
        Icons.error_outline_rounded,
        KPopTint.bubblegum,
        l10n.taskFailed,
      ),
      _ => (Icons.radio_button_unchecked, KPopTint.lavender, l10n.taskPending),
    };
    final fg = tint.foreground(scheme);
    return Semantics(
      label: '${task.label}: $hint',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: tint.background(scheme),
          borderRadius: BorderRadius.circular(KPopRadius.chip),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                task.label,
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(color: fg, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatPanel extends StatelessWidget {
  const _ChatPanel({
    required this.state,
    required this.session,
    required this.stage,
    required this.short,
    required this.height,
  });
  final _KiuBuilderPageState state;
  final AgentSession session;
  final Widget stage;
  final bool short;

  /// Height the panel really has (keyboard and app bar already removed).
  final double height;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = state._c;
    final msgs = session.messages;
    final last = msgs.isEmpty ? null : msgs.last;
    final replies = last != null && last.fromKiu && !c.sending
        ? (last.question?.quickReplies.isNotEmpty ?? false
              ? last.question!.quickReplies
              : last.quickReplies)
        : const <QuickReply>[];
    final pending = session.pending;
    final error = c.sendError;
    final sendError = error == null
        ? null
        : Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: KPopSpace.xs),
              child: Text(
                error.isNotEmpty ? error : l10n.errorGeneric,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          );
    final hasFiles =
        session.files.isNotEmpty ||
        c.pendingUploads.isNotEmpty ||
        c.uploadErrors.isNotEmpty;
    final canSkip = pending != null && !pending.essential;
    final lastItems = <Widget>[
      if (short && !session.published && canSkip)
        Align(
          alignment: Alignment.centerRight,
          child: _SkipQuestion(state: state),
        ),
      if (short && hasFiles) _FilesStrip(state: state, session: session),
      if (c.pendingText != null) _Bubble.user(c.pendingText!),
      if (c.sending) const _Typing(),
      if (session.published && session.publication != null)
        _ShareCard(
          state: state,
          result: session.publication!,
          name: session.businessName,
        ),
      if (!c.sending &&
          (last?.question?.allowUpload ?? false) &&
          session.filesEnabled)
        Padding(
          padding: const EdgeInsets.only(left: 42, top: KPopSpace.xs),
          child: Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const Key('kiu-upload-catalog'),
              onPressed: c.uploading > 0 ? null : state._attach,
              icon: const Icon(Icons.upload_file_rounded),
              label: Text(l10n.uploadCatalog, textAlign: TextAlign.start),
            ),
          ),
        ),
      if (replies.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(left: 42, top: KPopSpace.xs),
          child: Wrap(
            spacing: KPopSpace.xs,
            runSpacing: KPopSpace.xs,
            children: [
              for (final r in replies)
                KPopChip(
                  key: Key('qr-${r.value}'),
                  icon: r.isPublish ? Icons.rocket_launch_outlined : null,
                  tint: r.isPublish ? KPopTint.bubblegum : KPopTint.lavender,
                  label: r.label,
                  onPressed: c.publishing ? null : () => state._quick(r),
                ),
            ],
          ),
        ),
      if (session.started &&
          !session.published &&
          session.pending == null &&
          !state._revealed)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: KPopSpace.xs),
          child: Wrap(
            spacing: KPopSpace.xs,
            runSpacing: KPopSpace.xxs,
            children: [for (final task in session.tasks) _TaskChip(task: task)],
          ),
        ),
    ];
    if (short) {
      lastItems.add(stage);
      if (sendError != null) lastItems.add(sendError);
    }
    return Column(
      children: [
        if (!short) ...[
          const SizedBox(height: KPopSpace.xs),
          // Never more than half the panel: the conversation keeps its room.
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: height * .5),
            child: SingleChildScrollView(
              clipBehavior: Clip.none,
              child: KeyedSubtree(key: const Key('kiu-bubble'), child: stage),
            ),
          ),
        ],
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                // Messages dissolve under the stage instead of being cut.
                child: ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (rect) => LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: const [Colors.transparent, Colors.black],
                    stops: [0, (18 / rect.height).clamp(0.0, 1.0)],
                  ).createShader(rect),
                  child: ListView.builder(
                    controller: state._scroll,
                    reverse: true,
                    padding: const EdgeInsets.symmetric(vertical: KPopSpace.sm),
                    itemCount: msgs.length + lastItems.length,
                    itemBuilder: (context, index) {
                      if (index < lastItems.length) {
                        return lastItems[lastItems.length - 1 - index];
                      }
                      final m =
                          msgs[msgs.length - 1 - (index - lastItems.length)];
                      return _Bubble(message: m);
                    },
                  ),
                ),
              ),
              if (state._awayFromBottom)
                Positioned(
                  right: 12,
                  bottom: 8,
                  child: FloatingActionButton.small(
                    key: const Key('kiu-scroll-latest'),
                    tooltip: l10n.scrollToLatest,
                    onPressed: state._scrollToLatest,
                    child: const Icon(Icons.keyboard_arrow_down_rounded),
                  ),
                ),
            ],
          ),
        ),
        if (!short && sendError != null)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 88),
            child: SingleChildScrollView(child: sendError),
          ),
        if (!short && hasFiles)
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: c.pendingUploads.isEmpty ? 110 : height * .3,
            ),
            child: SingleChildScrollView(
              child: _FilesStrip(state: state, session: session),
            ),
          ),
        if (!session.published && !session.started && !state._intakeChosen)
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: height * .6),
            child: SingleChildScrollView(
              child: _IntakeChooser(state: state, short: short),
            ),
          )
        else if (!session.published)
          _Composer(
            state: state,
            short: short,
            hint: state._adjusting && session.ready
                ? l10n.adjustHint
                : session.started
                ? l10n.composerHintAnswer
                : l10n.composerHintFirst,
            canSkip: !short && canSkip,
          ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message}) : pendingText = null;
  const _Bubble.user(String text) : message = null, pendingText = text;
  final ChatMessage? message;
  final String? pendingText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final m = message;
    final fromKiu = m?.fromKiu ?? false;
    final text = m?.text ?? pendingText!;
    final reason = m?.question?.reason ?? '';
    // Discovery plan (Kiu's diagnosis) and the per-channel kit are long,
    // important messages: they get a tinted card and a small heading.
    final highlight = m?.kind == 'plan' || m?.kind == 'kit';
    final ready = m?.kind == 'ready';
    final tint = ready
        ? KPopTint.bubblegum
        : highlight
        ? KPopTint.lavender
        : null;
    final background = !fromKiu
        ? scheme.primary
        : tint?.background(scheme) ?? scheme.surface;
    final foreground = !fromKiu
        ? scheme.onPrimary
        : tint?.foreground(scheme) ?? scheme.onSurface;
    final bubble = Container(
      constraints: BoxConstraints(maxWidth: highlight ? 480 : 380),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: fromKiu && tint == null
            ? Border.all(color: scheme.outlineVariant)
            : null,
        color: background,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(22),
          topRight: const Radius.circular(22),
          bottomLeft: Radius.circular(fromKiu ? 6 : 22),
          bottomRight: Radius.circular(fromKiu ? 22 : 6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (m?.kind == 'plan') ...[
            Row(
              children: [
                Icon(Icons.insights_rounded, size: 16, color: foreground),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    l10n.kiuDiagnosis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: foreground,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          SelectableText(
            text,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: foreground,
              height: 1.45,
            ),
          ),
          if (reason.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 14,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    reason,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
    return Semantics(
      container: true,
      // Screen readers hear who is speaking; Kiu's new messages are announced.
      liveRegion: fromKiu && pendingText == null,
      label: fromKiu ? l10n.kiuSaid : l10n.youSaid,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          mainAxisAlignment: fromKiu
              ? MainAxisAlignment.start
              : MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (fromKiu) ...[const KiuAvatar(), const SizedBox(width: 8)],
            Flexible(child: bubble),
          ],
        ),
      ),
    );
  }
}

class _Typing extends StatelessWidget {
  const _Typing();
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const KiuAvatar(),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: KPopTint.lavender.background(scheme),
                borderRadius: BorderRadius.circular(KPopRadius.chip),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      AppLocalizations.of(context).kiuThinking,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: KPopTint.lavender.foreground(scheme),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: KPopTint.lavender.foreground(scheme),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A single ceramic pill: tools, the field and a round send button. Below
/// 360 dp (or with very large text) the tools move to a row of their own so
/// the field keeps a usable width.
class _Composer extends StatelessWidget {
  const _Composer({
    required this.state,
    required this.hint,
    required this.canSkip,
    required this.short,
  });
  final _KiuBuilderPageState state;
  final String hint;
  final bool canSkip, short;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final c = state._c;
    final tools = <Widget>[
      if (c.session?.filesEnabled ?? false)
        IconButton(
          key: const Key('kiu-attach'),
          tooltip: l10n.attachFiles,
          onPressed: c.sending || c.uploading > 0 ? null : state._attach,
          icon: const Icon(Icons.add_circle_outline_rounded),
        ),
      if (state._speech.enabled)
        IconButton(
          key: const Key('kiu-voice'),
          tooltip: l10n.voiceTitle,
          onPressed: c.sending ? null : state._openVoice,
          icon: const Icon(Icons.mic_none_rounded),
        )
      else if (state.widget.services.platform.dictationAvailable())
        IconButton(
          key: const Key('kiu-mic'),
          tooltip: state._listening ? l10n.micStop : l10n.micStart,
          onPressed: c.sending ? null : state._toggleDictation,
          isSelected: state._listening,
          style: state._listening
              ? IconButton.styleFrom(
                  backgroundColor: KPopTint.bubblegum.background(scheme),
                  foregroundColor: KPopTint.bubblegum.foreground(scheme),
                )
              : null,
          selectedIcon: const Icon(Icons.graphic_eq_rounded),
          icon: const Icon(Icons.mic_none_rounded),
        ),
    ];
    final canSend = !c.sending && !c.publishing;
    final send = IconButton.filled(
      key: const Key('kiu-send'),
      tooltip: l10n.send,
      style: IconButton.styleFrom(
        minimumSize: const Size.square(48),
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        disabledBackgroundColor: scheme.onSurface.withValues(alpha: .10),
        disabledForegroundColor: scheme.onSurface.withValues(alpha: .38),
      ),
      onPressed: canSend ? () => state._send() : null,
      // Explicit glyph color: readable on the ink (light) and peach (dark)
      // fill regardless of how the button resolves its foreground.
      icon: Icon(
        Icons.arrow_upward_rounded,
        color: canSend
            ? scheme.onPrimary
            : scheme.onSurface.withValues(alpha: .38),
      ),
    );
    final field = Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): _SendIntent(),
      },
      child: Actions(
        actions: {
          _SendIntent: CallbackAction<_SendIntent>(
            onInvoke: (_) => state._send(),
          ),
        },
        child: KPopInput(
          key: const Key('kiu-input'),
          controller: state._input,
          focusNode: state._focus,
          hint: hint,
          maxLines: short ? 1 : 4,
          enabled: !c.publishing,
          onSubmitted: state._send,
          borderless: true,
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: KPopSpace.xs, top: KPopSpace.xxs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (canSkip)
            Align(
              alignment: Alignment.centerRight,
              child: _SkipQuestion(state: state),
            ),
          LayoutBuilder(
            builder: (context, box) {
              final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
              final inline = box.maxWidth >= 340 * textScale.clamp(1, 1.4);
              return KPopSurface(
                radius: KPopRadius.card,
                raised: true,
                padding: const EdgeInsets.all(KPopSpace.xxs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (inline) ...tools,
                        Expanded(child: field),
                        const SizedBox(width: KPopSpace.xxs),
                        send,
                      ],
                    ),
                    if (!inline && tools.isNotEmpty) Row(children: tools),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// "¿Cómo querés contarle tu idea a Kiu?": talk (primary) or write.
class _IntakeChooser extends StatelessWidget {
  const _IntakeChooser({required this.state, required this.short});
  final _KiuBuilderPageState state;
  final bool short;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final voiceOn = state._speech.enabled;
    Widget card({
      required Key key,
      required IconData icon,
      required KPopTint tint,
      required String title,
      required String body,
      required VoidCallback onTap,
      bool primary = false,
    }) => Semantics(
      button: true,
      label: '$title. $body',
      excludeSemantics: true,
      child: KPopSurface(
        key: key,
        radius: KPopRadius.card,
        raised: primary,
        color: primary ? tint.background(scheme) : scheme.surface,
        padding: const EdgeInsets.all(KPopSpace.md),
        onTap: onTap,
        child: Row(
          children: [
            KPopIconBubble(
              icon: icon,
              tint: tint,
              size: 52,
              background: primary ? scheme.surface : null,
            ),
            const SizedBox(width: KPopSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: primary ? tint.foreground(scheme) : null,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (!short)
                    Text(
                      body,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: primary
                            ? tint.foreground(scheme).withValues(alpha: .86)
                            : null,
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: primary
                  ? tint.foreground(scheme)
                  : scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: KPopSpace.xs, top: KPopSpace.xxs),
      child: Column(
        key: const Key('intake-chooser'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              l10n.intakeTitle,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
          ),
          if (!short) ...[
            const SizedBox(height: KPopSpace.xxs),
            Text(
              l10n.intakeFree,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: KPopSpace.sm),
          card(
            key: const Key('intake-voice'),
            icon: Icons.mic_rounded,
            tint: KPopTint.bubblegum,
            title: l10n.intakeVoiceTitle,
            body: voiceOn ? l10n.intakeVoiceBody : l10n.intakeVoiceOff,
            onTap: () => state._chooseIntake(audio: true),
            primary: voiceOn,
          ),
          const SizedBox(height: KPopSpace.xs),
          card(
            key: const Key('intake-text'),
            icon: Icons.edit_note_rounded,
            tint: KPopTint.lavender,
            title: l10n.intakeTextTitle,
            body: l10n.intakeTextBody,
            onTap: () => state._chooseIntake(audio: false),
            primary: !voiceOn,
          ),
        ],
      ),
    );
  }
}

class _SkipQuestion extends StatelessWidget {
  const _SkipQuestion({required this.state});
  final _KiuBuilderPageState state;

  @override
  Widget build(BuildContext context) => TextButton(
    key: const Key('skip-question'),
    onPressed: state._c.sending ? null : () => state._send('omitir'),
    child: Text(AppLocalizations.of(context).skipQuestion),
  );
}

class _SendIntent extends Intent {
  const _SendIntent();
}

class _PreviewPanel extends StatelessWidget {
  const _PreviewPanel({required this.state, required this.session});
  final _KiuBuilderPageState state;
  final AgentSession session;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final view = state._c.preview;
    if (view != null && !state._revealed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(KPopSpace.md),
            child: Semantics(
              liveRegion: true,
              child: Text(l10n.previewBuilding),
            ),
          ),
          Expanded(
            child: ExcludeFocus(
              child: ExcludeSemantics(
                child: IgnorePointer(
                  child: StorefrontRenderer(
                    view: view,
                    imageUri: state.widget.services.storefront.imageUri,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }
    if (view == null) {
      final error = state._c.previewFailure;
      return MessageState(
        icon: error != null
            ? Icons.cloud_off_outlined
            : Icons.storefront_outlined,
        title: l10n.previewTitle,
        body: error != null
            ? failureMessage(context, error)
            : session.status == 'building' || session.ready
            ? l10n.previewBuilding
            : l10n.previewEmpty,
        actionLabel: error == null ? null : l10n.retry,
        onAction: error == null ? null : state._c.loadPreview,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PreviewBar(state: state, session: session, view: view),
        if (state._c.previewFailure case final ApiFailure<Object?> failure)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: KPopSpace.md),
            child: OverflowBar(
              alignment: MainAxisAlignment.spaceBetween,
              children: [
                Semantics(
                  liveRegion: true,
                  child: Text(failureMessage(context, failure)),
                ),
                TextButton(
                  onPressed: state._c.loadPreview,
                  child: Text(l10n.retry),
                ),
              ],
            ),
          ),
        Expanded(
          child: StorefrontRenderer(
            view: view,
            imageUri: state.widget.services.storefront.imageUri,
            onContact: session.published && view.contact.whatsappUrl.isNotEmpty
                ? () => state.widget.services.platform.openUrl(
                    Uri.parse(view.contact.whatsappUrl),
                  )
                : null,
          ),
        ),
      ],
    );
  }
}

class _PreviewBar extends StatelessWidget {
  const _PreviewBar({
    required this.state,
    required this.session,
    required this.view,
  });
  final _KiuBuilderPageState state;
  final AgentSession session;
  final StorefrontView view;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                session.published ? l10n.previewPublished : l10n.previewDraft,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (session.ready && !session.published)
              FilledButton.icon(
                key: const Key('publish-button'),
                onPressed: state._c.publishing ? null : state._confirmPublish,
                icon: const Icon(Icons.rocket_launch_outlined),
                label: Text(l10n.publishCta),
              ),
          ],
        ),
      ),
    );
  }
}

class _ShareCard extends StatelessWidget {
  const _ShareCard({
    required this.state,
    required this.result,
    required this.name,
  });
  final _KiuBuilderPageState state;
  final PublishResult result;
  final String name;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final p = state.widget.services.platform;
    final link = result.shareUrl;
    final text = l10n.shareText(name);
    final fg = KPopTint.bubblegum.foreground(scheme);
    return Padding(
      padding: const EdgeInsets.only(top: 12, left: 42),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(KPopRadius.card),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              KPopTint.bubblegum.background(scheme),
              if (scheme.brightness == Brightness.dark)
                KPopTint.lavender.background(scheme)
              else
                KPopTint.peach.background(scheme),
            ],
          ),
          boxShadow: KPopElevation.soft(scheme.brightness),
        ),
        child: Padding(
          padding: const EdgeInsets.all(KPopSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.shareTitle,
                style: theme.textTheme.titleLarge?.copyWith(color: fg),
              ),
              const SizedBox(height: KPopSpace.xs),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: KPopSpace.sm,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(KPopRadius.control),
                ),
                child: SelectableText(
                  link,
                  key: const Key('share-link'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.secondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: KPopSpace.sm),
              Wrap(
                spacing: KPopSpace.xs,
                runSpacing: KPopSpace.xs,
                children: [
                  FilledButton.icon(
                    key: const Key('share-native'),
                    onPressed: () async {
                      state._shared('native');
                      final shared = await p.share(name, text, link);
                      if (!shared) {
                        await p.copyText(link);
                        if (context.mounted) {
                          showSnack(context, l10n.linkCopied);
                        }
                      }
                    },
                    icon: const Icon(Icons.ios_share_rounded),
                    label: Text(l10n.share),
                  ),
                  OutlinedButton.icon(
                    key: const Key('share-copy'),
                    onPressed: () async {
                      state._shared('copy');
                      await p.copyText(link);
                      if (context.mounted) showSnack(context, l10n.linkCopied);
                    },
                    icon: const Icon(Icons.copy_rounded),
                    label: Text(l10n.copyLink),
                  ),
                  OutlinedButton.icon(
                    key: const Key('share-whatsapp'),
                    onPressed: () {
                      state._shared('whatsapp');
                      p.openUrl(
                        Uri.https('wa.me', '/', {'text': '$text $link'}),
                      );
                    },
                    icon: const Icon(Icons.chat_rounded),
                    label: const Text('WhatsApp'),
                  ),
                  OutlinedButton.icon(
                    key: const Key('share-facebook'),
                    onPressed: () {
                      state._shared('facebook');
                      p.openUrl(
                        Uri.https('www.facebook.com', '/sharer/sharer.php', {
                          'u': link,
                        }),
                      );
                    },
                    icon: const Icon(Icons.facebook_rounded),
                    label: const Text('Facebook'),
                  ),
                ],
              ),
              const SizedBox(height: KPopSpace.xs),
              Wrap(
                spacing: KPopSpace.xxs,
                children: [
                  TextButton.icon(
                    key: const Key('open-store'),
                    style: TextButton.styleFrom(foregroundColor: fg),
                    onPressed: () => state.context.go('/s/${result.slug}'),
                    icon: const Icon(Icons.storefront_outlined),
                    label: Text(l10n.openMyStore),
                  ),
                  TextButton.icon(
                    key: const Key('new-store'),
                    style: TextButton.styleFrom(foregroundColor: fg),
                    onPressed: () => state._c.start(fresh: true),
                    icon: const Icon(Icons.add_business_outlined),
                    label: Text(l10n.createAnotherStore),
                  ),
                  TextButton.icon(
                    key: const Key('go-admin'),
                    style: TextButton.styleFrom(foregroundColor: fg),
                    onPressed: () => state.context.go('/admin'),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: Text(l10n.addPhotosInAdmin),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Files shared with Kiu, each with its own status (processed independently).
class _FilesStrip extends StatelessWidget {
  const _FilesStrip({required this.state, required this.session});
  final _KiuBuilderPageState state;
  final AgentSession session;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final c = state._c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final f in session.files)
                Tooltip(
                  message: f.note.isEmpty ? _status(l10n, f.status) : f.note,
                  child: Chip(
                    key: Key('file-${f.filename}'),
                    visualDensity: VisualDensity.compact,
                    avatar: f.busy
                        ? const SizedBox.square(
                            dimension: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            switch (f.status) {
                              'processed' => Icons.check_circle_rounded,
                              'needs_review' => Icons.info_outline_rounded,
                              _ => Icons.error_outline_rounded,
                            },
                            size: 16,
                            color: f.status == 'processed'
                                ? AppTheme.success(scheme)
                                : f.status == 'needs_review'
                                ? scheme.tertiary
                                : scheme.error,
                          ),
                    label: Text(
                      '${f.filename} · ${_status(l10n, f.status)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
            ],
          ),
          for (final u in c.pendingUploads) _UploadRow(c: c, upload: u),
          for (final e in c.uploadErrors)
            Text(e, style: TextStyle(color: scheme.error, fontSize: 12)),
        ],
      ),
    );
  }

  String _status(AppLocalizations l10n, String s) => switch (s) {
    'received' => l10n.fileReceived,
    'processing' => l10n.fileProcessing,
    'processed' => l10n.fileProcessed,
    'needs_review' => l10n.fileNeedsReview,
    _ => l10n.fileError,
  };
}

/// One file on its way: progress and cancel, or the error with retry/remove.
class _UploadRow extends StatelessWidget {
  const _UploadRow({required this.c, required this.upload});
  final KiuController c;
  final PendingUpload upload;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = upload.file.name;
    final failed = upload.failed;
    return Padding(
      key: Key('upload-${upload.id}'),
      padding: const EdgeInsets.only(top: KPopSpace.xs),
      child: KPopSurface(
        flat: true,
        radius: KPopRadius.tile,
        color: failed
            ? KPopTint.bubblegum.background(scheme)
            : KPopTint.babyBlue.background(scheme),
        padding: const EdgeInsets.fromLTRB(KPopSpace.sm, 4, 4, 4),
        child: Row(
          children: [
            Icon(
              failed ? Icons.error_outline_rounded : Icons.upload_rounded,
              size: 18,
              color: failed
                  ? KPopTint.bubblegum.foreground(scheme)
                  : KPopTint.babyBlue.foreground(scheme),
            ),
            const SizedBox(width: KPopSpace.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    failed && (upload.error ?? '').isNotEmpty
                        ? '$name: ${upload.error}'
                        : failed
                        ? name
                        : l10n.uploadSending(name),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: failed
                          ? KPopTint.bubblegum.foreground(scheme)
                          : KPopTint.babyBlue.foreground(scheme),
                    ),
                  ),
                  if (!failed) ...[
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(KPopRadius.chip),
                      child: LinearProgressIndicator(
                        value: upload.progress >= 1 ? null : upload.progress,
                        minHeight: 4,
                        semanticsLabel: l10n.uploadSending(name),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (failed) ...[
              TextButton(
                key: Key('upload-retry-${upload.id}'),
                onPressed: () => c.retryUpload(upload),
                child: Text(l10n.uploadRetry),
              ),
              IconButton(
                key: Key('upload-remove-${upload.id}'),
                tooltip: l10n.uploadRemove,
                onPressed: () => c.removeUpload(upload),
                icon: const Icon(Icons.close_rounded),
              ),
            ] else
              IconButton(
                key: Key('upload-cancel-${upload.id}'),
                tooltip: l10n.uploadCancel(name),
                onPressed: () => c.cancelUpload(upload),
                icon: const Icon(Icons.close_rounded),
              ),
          ],
        ),
      ),
    );
  }
}
