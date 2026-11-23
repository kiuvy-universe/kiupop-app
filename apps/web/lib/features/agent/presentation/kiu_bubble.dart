import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/motion/reduced_motion.dart';
import '../../../core/theme/app_theme.dart';

/// Product states of Kiu. The builder maps backend facts to these:
/// idle → listening → thinking → processing (bubble inflates with confirmed
/// progress) → pop (only after `store.ready`) → celebrate / success.
enum KiuMood {
  idle,
  greeting,
  listening,
  thinking,
  processing,
  success,
  error,
  celebrate,
}

/// A compact, static Kiu for messages.
class KiuAvatar extends StatelessWidget {
  const KiuAvatar({super.key, this.size = 34});

  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: RepaintBoundary(
      child: CustomPaint(
        size: Size.square(size),
        painter: _KiuPainter(
          mood: KiuMood.idle,
          small: true,
          dark: Theme.of(context).brightness == Brightness.dark,
        ),
      ),
    ),
  );
}

/// Draws Kiu and an elastic, pink bubble from confirmed build progress.
/// The owning session requests one POP after receiving store.ready.
class KiuBubbleAnimation extends StatefulWidget {
  const KiuBubbleAnimation({
    super.key,
    this.progress = 0,
    this.mood = KiuMood.idle,
    this.pop = false,
    this.onPopped,
    this.size = 160,
  });

  final double progress;
  final KiuMood mood;
  final bool pop;
  final VoidCallback? onPopped;
  final double size;

  @override
  State<KiuBubbleAnimation> createState() => _KiuBubbleAnimationState();
}

class _KiuBubbleAnimationState extends State<KiuBubbleAnimation>
    with TickerProviderStateMixin {
  late final _ambient = AnimationController(
    vsync: this,
    duration: KPopMotion.floatCycle,
  );
  late final _progress = AnimationController(
    vsync: this,
    duration: KPopMotion.slow,
    value: _targetProgress,
  );
  late final _greeting = AnimationController(
    vsync: this,
    duration: KPopMotion.greeting,
  );
  late final _pop = AnimationController(vsync: this, duration: KPopMotion.pop)
    ..addStatusListener((status) {
      if (status == AnimationStatus.completed && widget.pop) _finishPop();
    });
  late final _frames = Listenable.merge([_ambient, _progress, _greeting, _pop]);
  late final AppLifecycleListener _lifecycle;
  bool _visible = true;
  bool _reduced = false;

  /// Reduced motion is a choice; a covered route or a hidden app is a pause.
  bool _motionOff = false;
  bool _popStarted = false;
  bool _popFinished = false;
  bool _greeted = false;

  double get _targetProgress => widget.progress.clamp(0.0, 1.0);
  bool get _animate => _visible && !_reduced;

  @override
  void initState() {
    super.initState();
    final state = WidgetsBinding.instance.lifecycleState;
    _visible = state == null || state == AppLifecycleState.resumed;
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        setState(() => _visible = state == AppLifecycleState.resumed);
        _sync();
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motionOff =
        MediaQuery.disableAnimationsOf(context) || systemPrefersReducedMotion();
    _reduced = !TickerMode.valuesOf(context).enabled || _motionOff;
    _sync();
  }

  @override
  void didUpdateWidget(KiuBubbleAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  /// Active conversation: Kiu keeps breathing while it listens or works.
  static const _loopMoods = {
    KiuMood.listening,
    KiuMood.thinking,
    KiuMood.processing,
  };

  /// Resting moods breathe for one cycle and then hold still, so nothing on
  /// screen animates forever while the person reads or decides.
  static const _onceMoods = {
    KiuMood.idle,
    KiuMood.greeting,
    KiuMood.success,
    KiuMood.celebrate,
  };

  bool _looping = false;
  KiuMood? _restedFor;

  void _sync() {
    final mood = widget.mood;
    final free = _animate && !widget.pop;
    if (free && _loopMoods.contains(mood)) {
      if (!_looping) {
        _looping = true;
        _restedFor = null;
        _ambient.repeat();
      }
    } else if (free && _onceMoods.contains(mood)) {
      if (_looping) {
        // Finish the current breath, then rest.
        _looping = false;
        _restedFor = mood;
        _ambient.forward();
      } else if (_restedFor != mood) {
        _restedFor = mood;
        _ambient.forward(from: 0);
      }
    } else {
      _looping = false;
      _ambient.stop();
    }
    if (_animate && mood == KiuMood.processing) {
      if (_targetProgress != _progressTarget) {
        _progressTarget = _targetProgress;
        _progress.animateTo(_targetProgress, curve: KPopMotion.ease);
      }
    } else {
      _progressTarget = _targetProgress;
      _progress.value = _targetProgress;
    }
    if (_animate && mood == KiuMood.greeting && !_greeted) {
      _greeted = true;
      _greeting.forward();
    } else if (!_animate || mood != KiuMood.greeting) {
      _greeting.stop();
    }
    if (mood == KiuMood.error) {
      if (widget.pop && !_popFinished) {
        _pop.stop();
        _queueFinish();
      }
      return;
    }
    if (!widget.pop) {
      _pop.stop();
      return;
    }
    if (_popFinished) return;
    if (_motionOff) {
      // Reduced motion: the result appears at once, no celebration.
      _pop.stop();
      _popStarted = true;
      _queueFinish();
    } else if (!_animate) {
      // Covered or in the background: keep the POP for when Kiu is visible.
      _pop.stop();
    } else if (!_popStarted || !_pop.isAnimating) {
      _popStarted = true;
      _pop.forward();
    }
  }

  double? _progressTarget;

  void _queueFinish() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.pop) _finishPop();
    });
  }

  void _finishPop() {
    if (_popFinished) return;
    _popFinished = true;
    widget.onPopped?.call();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _ambient.dispose();
    _progress.dispose();
    _greeting.dispose();
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: RepaintBoundary(
      child: SizedBox.square(
        dimension: widget.size,
        child: CustomPaint(
          willChange: _animate && (_ambient.isAnimating || widget.pop),
          painter: _KiuPainter(
            repaint: _frames,
            mood: widget.mood,
            ambient: _animate ? _ambient : null,
            progress: _progress,
            greeting: _animate ? _greeting : null,
            pop: _animate && widget.pop ? _pop : null,
            dark: Theme.of(context).brightness == Brightness.dark,
          ),
        ),
      ),
    ),
  );
}

/// Ceramic Kiu (KCS-002 identity): a matte, rounded figurine of soft energy
/// with large expressive eyes and two floating orb-hands. No arms, no fingers,
/// no plasma veins, no bloom. Geometry follows KIU_CHARACTER_BIBLE §4 ratios.
/// All frame changes repaint this canvas without rebuilding the widget tree.
class _KiuPainter extends CustomPainter {
  _KiuPainter({
    super.repaint,
    required this.mood,
    this.ambient,
    this.progress,
    this.greeting,
    this.pop,
    this.small = false,
    this.dark = false,
  });

  final KiuMood mood;
  final Animation<double>? ambient, progress, greeting, pop;
  final bool small;
  final bool dark;

  // Matte ceramic violet body.
  static const _glaze = Color(0xFFF6F0FF);
  static const _bodyLight = Color(0xFFD0BBFF);
  static const _body = Color(0xFFA584F0);
  static const _bodyShade = Color(0xFF7350D2);
  static const _rimWarm = Color(0xFFFFE9D2);
  static const _ink = Color(0xFF2B2140);
  static const _iris = Color(0xFF5B3F8E);
  static const _white = Color(0xFFFFFFFF);
  static const _cheek = Color(0xFFFF9EC4);
  static const _gum = Color(0xFFF2B5D6);
  static const _gumDeep = Color(0xFFE88DBC);
  static const _shadow = Color(0xFF4B3A6A);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 160;
    canvas.save();
    canvas.translate((size.width - 160 * scale) / 2, 0);
    canvas.scale(scale);
    final phase = ambient?.value ?? 0;
    final burst = pop?.value ?? 0;
    final wave = greeting?.value ?? 0;
    final t = phase * 2 * math.pi;
    // Breath: ~3 cycles per 10 s loop; hands drift on their own rhythms.
    final float = math.sin(t * 3);
    final celebrating =
        (burst >= .40 && burst < 1) || mood == KiuMood.celebrate;
    final bounce = celebrating
        ? math.sin(((burst - .4) / .6).clamp(0.0, 1.0) * math.pi)
        : 0.0;
    final blinking = phase > .965 && phase < .986;
    final thinking = mood == KiuMood.thinking;
    final listening = mood == KiuMood.listening;
    final concerned = mood == KiuMood.error;
    final happy = celebrating || mood == KiuMood.success;
    final building = mood == KiuMood.processing;
    final r = small ? 70.0 : 48.0;
    final lift = thinking ? 1.6 : 3.0;
    final center = small
        ? const Offset(80, 80)
        : Offset(78, 72 - float * lift - bounce.abs() * 10);
    final brush = Paint();

    if (!small) {
      // Contact shadow that breathes with the float.
      brush
        ..color = _shadow.withValues(alpha: .14 - .03 * float)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawOval(
        Rect.fromCenter(
          center: const Offset(78, 140),
          width: 72 - 6 * float,
          height: 11,
        ),
        brush,
      );
      brush.maskFilter = null;
      _hands(
        canvas,
        brush,
        center,
        r,
        t,
        wave,
        happy,
        thinking,
        listening,
        concerned,
      );
    }

    canvas.translate(center.dx, center.dy);
    // Gentle lean while listening; squash & stretch on bounce.
    if (listening && !small) canvas.rotate(-.05 + .02 * float);
    final squash = 1 + float * .012 + bounce * .04;
    canvas.scale(squash, 1 / squash);

    _paintBody(canvas, brush, r);

    for (final side in [-1, 1]) {
      _paintCheek(canvas, brush, r, side, happy);
      _eye(canvas, brush, r, side, blinking, thinking, happy, concerned);
      if (!small) _brow(canvas, brush, r, side, thinking, concerned);
    }
    _mouth(canvas, brush, r, happy, concerned, building, burst);

    if (building || (burst > 0 && burst < 1)) {
      _bubble(canvas, brush, r, burst);
    }
    canvas.restore();
  }

  void _paintBody(Canvas canvas, Paint brush, double r) {
    // Matte base with a soft top-left light and a shaded lower-right.
    brush
      ..style = PaintingStyle.fill
      ..color = _white
      ..shader = ui.Gradient.radial(
        Offset(-r * .35, -r * .45),
        r * 1.35,
        const [_glaze, _bodyLight, _body, _bodyShade],
        const [0, .1, .45, 1],
      );
    canvas.drawCircle(Offset.zero, r, brush);
    // Warm rim light from below-right: the ceramic bounce light.
    brush.shader = ui.Gradient.radial(
      Offset(r * .55, r * .7),
      r * 1.1,
      [_rimWarm.withValues(alpha: .38), _rimWarm.withValues(alpha: 0)],
      const [.55, 1],
    );
    canvas.drawCircle(Offset.zero, r, brush);
    // Matte specular: a soft elliptical highlight, not a glossy dot.
    brush
      ..shader = null
      ..color = _white.withValues(alpha: .5)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(-r * .40, -r * .52),
        width: r * .62,
        height: r * .34,
      ),
      brush,
    );
    brush.maskFilter = null;
    // Hairline edge keeps the figure crisp on cream backgrounds.
    brush
      ..style = PaintingStyle.stroke
      ..strokeWidth = small ? 1.4 : 1
      ..color = _bodyShade.withValues(alpha: .35);
    canvas.drawCircle(Offset.zero, r - .5, brush);
  }

  void _hands(
    Canvas canvas,
    Paint brush,
    Offset center,
    double r,
    double t,
    double wave,
    bool happy,
    bool thinking,
    bool listening,
    bool concerned,
  ) {
    for (final side in [-1, 1]) {
      final own = math.sin(t * (side == 1 ? 2.3 : 1.7) + side * 1.1);
      final drift = math.cos(t * 1.3 + side * .6);
      final waving = side == 1 && wave > 0 && wave < 1;
      double x = r * 1.28 * side + drift * 1.8;
      double y = r * .38 + own * 2.6;
      if (waving) {
        final arc = math.sin(wave * 4 * math.pi);
        x = r * 1.22 + arc * 4;
        y = -r * .55 + arc * 6;
      } else if (thinking && side == 1) {
        x = r * .78;
        y = r * .62 + own * 1.2;
      } else if (happy) {
        y = -r * .35 + own * 3;
        x = r * 1.3 * side;
      } else if (listening) {
        y = r * .18 + own * 2;
      } else if (concerned) {
        y = r * .6 + own;
        x = r * 1.12 * side;
      }
      _orb(canvas, brush, center + Offset(x, y), small ? 0 : 10.5);
    }
  }

  /// One floating orb-hand: the same ceramic material as the body, smaller.
  void _orb(Canvas canvas, Paint brush, Offset at, double radius) {
    brush
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3)
      ..color = _shadow.withValues(alpha: .12)
      ..shader = null;
    canvas.drawCircle(at.translate(0, radius * .9), radius * .85, brush);
    brush
      ..maskFilter = null
      ..color = _white
      ..shader = ui.Gradient.radial(
        at.translate(-radius * .35, -radius * .4),
        radius * 1.15,
        const [_glaze, _bodyLight, _body, _bodyShade],
        const [0, .1, .45, 1],
      );
    canvas.drawCircle(at, radius, brush);
    brush
      ..shader = null
      ..color = _white.withValues(alpha: .55);
    canvas.drawOval(
      Rect.fromCenter(
        center: at.translate(-radius * .3, -radius * .4),
        width: radius * .7,
        height: radius * .4,
      ),
      brush,
    );
  }

  void _paintCheek(Canvas canvas, Paint brush, double r, int side, bool happy) {
    brush
      ..style = PaintingStyle.fill
      ..shader = null
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, small ? 4 : 2.5)
      ..color = _cheek.withValues(alpha: happy ? .85 : .7);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(side * r * .62, r * .33),
        width: r * .30,
        height: r * .20,
      ),
      brush,
    );
    brush.maskFilter = null;
  }

  void _eye(
    Canvas canvas,
    Paint brush,
    double r,
    int side,
    bool blinking,
    bool thinking,
    bool happy,
    bool concerned,
  ) {
    final center = Offset(side * r * .47, r * .02);
    final eye = r * (small ? .29 : .25);
    if (blinking || happy) {
      brush
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = small ? 4.2 : 2.6
        ..color = _ink;
      canvas.drawPath(
        Path()
          ..moveTo(center.dx - eye * .84, center.dy)
          ..quadraticBezierTo(
            center.dx,
            center.dy + (happy ? -eye * 1.1 : eye * .25),
            center.dx + eye * .84,
            center.dy,
          ),
        brush,
      );
      return;
    }
    brush
      ..style = PaintingStyle.fill
      ..shader = null
      ..color = _white;
    canvas.drawOval(
      Rect.fromCenter(
        center: center,
        width: eye * 1.8,
        height: eye * (concerned ? 1.6 : 2.05),
      ),
      brush,
    );
    final pupil = center.translate(
      thinking ? eye * .18 : 0,
      thinking ? -eye * .26 : eye * .06,
    );
    brush.color = _iris;
    canvas.drawCircle(pupil, eye * .74, brush);
    brush.color = _ink;
    canvas.drawCircle(pupil, eye * .56, brush);
    // Three sparkles (KIU_CHARACTER_BIBLE §3.4).
    brush.color = _white;
    canvas.drawCircle(
      pupil.translate(-eye * .24, -eye * .26),
      eye * .22,
      brush,
    );
    canvas.drawCircle(pupil.translate(eye * .26, eye * .24), eye * .10, brush);
    canvas.drawCircle(pupil.translate(eye * .22, -eye * .32), eye * .07, brush);
  }

  void _brow(
    Canvas canvas,
    Paint brush,
    double r,
    int side,
    bool thinking,
    bool concerned,
  ) {
    final center = Offset(side * r * .47, r * .02);
    final eye = r * .25;
    final raise = thinking && side == 1 ? 7.0 : 4.5;
    final brow = center.translate(0, -eye - raise);
    brush
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.8
      ..color = _ink.withValues(alpha: .55);
    canvas.drawPath(
      Path()
        ..moveTo(brow.dx - 5, brow.dy + (concerned ? -side * 1.5 : 0))
        ..quadraticBezierTo(
          brow.dx,
          brow.dy - 2.5,
          brow.dx + 5,
          brow.dy + (concerned ? side * 2.5 : 0),
        ),
      brush,
    );
  }

  void _mouth(
    Canvas canvas,
    Paint brush,
    double r,
    bool happy,
    bool concerned,
    bool building,
    double burst,
  ) {
    brush
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = small ? 3.6 : 2.1
      ..color = _ink;
    if (building && burst == 0) {
      // Lips round the gum: a small "o".
      brush.style = PaintingStyle.fill;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(0, r * .38),
          width: r * .16,
          height: r * .14,
        ),
        brush,
      );
      return;
    }
    if (happy) {
      brush.style = PaintingStyle.fill;
      final smile = Path()
        ..moveTo(-r * .16, r * .32)
        ..quadraticBezierTo(0, r * .62, r * .16, r * .32)
        ..close();
      canvas.drawPath(smile, brush);
      return;
    }
    final mouth = Path()
      ..moveTo(-r * .12, r * .34)
      ..quadraticBezierTo(0, r * (concerned ? .26 : .48), r * .12, r * .34);
    canvas.drawPath(mouth, brush);
  }

  /// Bubblegum: translucent pink, inflating from the mouth as the backend
  /// confirms progress; a short elastic swell, then the POP ring and drops.
  void _bubble(Canvas canvas, Paint brush, double r, double burst) {
    const peak = .40;
    final progressValue = progress?.value ?? 0;
    final radius = burst == 0
        ? 6 + progressValue * 24
        : 28 + KPopMotion.elastic.transform((burst / peak).clamp(0.0, 1.0)) * 9;
    final center = Offset(radius * .55, r * .38 + radius * .35);
    if (burst >= peak) {
      final t = ((burst - peak) / .42).clamp(0.0, 1.0);
      if (t >= 1) return;
      brush
        ..style = PaintingStyle.stroke
        ..shader = null
        ..maskFilter = null
        ..color = _gumDeep.withValues(alpha: .85 * (1 - t))
        ..strokeWidth = 2.2 * (1 - t) + .5;
      canvas.drawCircle(center, 32 + 16 * KPopMotion.ease.transform(t), brush);
      brush.style = PaintingStyle.fill;
      for (var i = 0; i < 9; i++) {
        final a = i * math.pi * 2 / 9 + .3;
        final distance = 20 + (26 + i % 3 * 4) * t;
        final point = center + Offset(math.cos(a), math.sin(a)) * distance;
        brush.color = (i.isEven ? _gum : _gumDeep).withValues(alpha: 1 - t);
        canvas.drawCircle(point, (2.6 + i % 2) * (1 - t), brush);
      }
      return;
    }
    final wobble = 1 + .03 * math.sin(burst * 19);
    final bubble = Rect.fromCenter(
      center: center,
      width: radius * 2 * wobble,
      height: radius * 1.96 / wobble,
    );
    brush
      ..style = PaintingStyle.fill
      ..maskFilter = null
      ..color = _white
      ..shader = ui.Gradient.radial(
        center.translate(-radius * .38, -radius * .42),
        radius * 1.5,
        [
          _white.withValues(alpha: .80),
          _gum.withValues(alpha: .66),
          _gumDeep.withValues(alpha: .78),
        ],
        const [0, .5, 1],
      );
    canvas.drawOval(bubble, brush);
    brush
      ..shader = null
      ..color = _white.withValues(alpha: .7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawOval(bubble, brush);
    brush
      ..style = PaintingStyle.fill
      ..color = _white.withValues(alpha: .55);
    canvas.drawOval(
      Rect.fromCenter(
        center: center.translate(-radius * .35, -radius * .45),
        width: radius * .5,
        height: radius * .28,
      ),
      brush,
    );
  }

  @override
  bool shouldRepaint(_KiuPainter oldDelegate) =>
      oldDelegate.mood != mood ||
      oldDelegate.ambient != ambient ||
      oldDelegate.greeting != greeting ||
      oldDelegate.pop != pop ||
      oldDelegate.progress != progress ||
      oldDelegate.small != small ||
      oldDelegate.dark != dark;
}
