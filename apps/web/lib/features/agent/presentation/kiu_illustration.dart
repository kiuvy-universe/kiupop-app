import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import 'kiu_bubble.dart';

/// Kiu on a pastel cloud stage: soft clay blobs behind a ceramic figurine.
/// Static backdrop (never repaints); only Kiu animates inside its own layer.
class KiuIllustration extends StatelessWidget {
  const KiuIllustration({
    super.key,
    this.height,
    this.mood = KiuMood.greeting,
    this.framed = true,
  });

  /// Fixed height, or null to fill the parent. Every layer is positioned, so
  /// the stage reports no intrinsic height and lets the page decide whether
  /// it fits without scrolling.
  final double? height;
  final KiuMood mood;

  /// Draws the rounded ceramic frame; `false` floats Kiu on the page itself.
  final bool framed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stage = Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(painter: _CloudBackdrop(scheme, framed: framed)),
          ),
        ),
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, box) => Align(
              alignment: const Alignment(0, .35),
              child: KiuBubbleAnimation(
                size: math.min(
                  math.min(box.maxWidth, box.maxHeight * 1.1) * .98,
                  360,
                ),
                mood: mood,
              ),
            ),
          ),
        ),
      ],
    );
    final decorated = framed
        ? DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(KPopRadius.hero),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: scheme.brightness == Brightness.dark
                    ? [
                        KPopTint.lavender.background(scheme),
                        scheme.surfaceContainerHigh,
                      ]
                    : [
                        KPopTint.lavender.background(scheme),
                        KPopTint.peach
                            .background(scheme)
                            .withValues(alpha: .75),
                      ],
              ),
              border: Border.all(color: scheme.outlineVariant),
              boxShadow: KPopElevation.soft(scheme.brightness),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(KPopRadius.hero),
              child: stage,
            ),
          )
        : stage;
    return ExcludeSemantics(
      child: height == null
          ? decorated
          : SizedBox(height: height, width: double.infinity, child: decorated),
    );
  }
}

class _CloudBackdrop extends CustomPainter {
  _CloudBackdrop(this.scheme, {required this.framed});
  final ColorScheme scheme;
  final bool framed;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final u = size.shortestSide;
    final dark = scheme.brightness == Brightness.dark;
    final brush = Paint()..style = PaintingStyle.fill;
    final alpha = dark ? .32 : .9;
    void cloud(Offset at, double w, Color color) {
      // A flat-bottomed cumulus: three puffs on a rounded base, with a soft
      // lower shade so it reads as clay, not as a blur.
      final h = w * .34;
      final shape = Path()
        ..addRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: at, width: w, height: h),
            Radius.circular(h / 2),
          ),
        )
        ..addOval(
          Rect.fromCircle(
            center: at.translate(-w * .2, -h * .35),
            radius: h * .55,
          ),
        )
        ..addOval(
          Rect.fromCircle(
            center: at.translate(w * .1, -h * .55),
            radius: h * .72,
          ),
        )
        ..addOval(
          Rect.fromCircle(
            center: at.translate(w * .32, -h * .2),
            radius: h * .42,
          ),
        );
      brush
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(
              color,
              Colors.white,
              dark ? .0 : .45,
            )!.withValues(alpha: alpha),
            color.withValues(alpha: alpha),
          ],
        ).createShader(Rect.fromCenter(center: at, width: w, height: h * 2.4))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, u * .004);
      canvas.drawPath(shape, brush);
      brush
        ..shader = null
        ..maskFilter = null;
    }

    cloud(
      c + Offset(-u * .40, u * .30),
      u * .58,
      KPopTint.peach.background(scheme),
    );
    cloud(
      c + Offset(u * .42, -u * .34),
      u * .42,
      KPopTint.bubblegum.background(scheme),
    );
    cloud(
      c + Offset(u * .40, u * .42),
      u * .62,
      KPopTint.mint.background(scheme),
    );
    cloud(
      c + Offset(-u * .46, -u * .30),
      u * .36,
      KPopTint.babyBlue.background(scheme),
    );
    // A few quiet sparkles.
    brush.color = (dark ? scheme.onSurface : KPopColors.violetDeep).withValues(
      alpha: .35,
    );
    for (final (dx, dy, r) in const [
      (-.46, -.40, 2.2),
      (.49, .05, 2.8),
      (.30, -.44, 1.6),
      (-.30, .48, 1.8),
    ]) {
      canvas.drawCircle(c + Offset(u * dx, u * dy), r, brush);
    }
    brush
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    for (final (dx, dy, s) in const [(.44, -.14, 5.0), (-.50, .12, 4.0)]) {
      final p = c + Offset(u * dx, u * dy);
      canvas.drawLine(p.translate(-s, 0), p.translate(s, 0), brush);
      canvas.drawLine(p.translate(0, -s), p.translate(0, s), brush);
    }
    if (!framed) return;
    // Soft inner vignette keeps the frame reading as a ceramic tile.
    brush
      ..style = PaintingStyle.fill
      ..shader = RadialGradient(
        colors: [
          Colors.transparent,
          scheme.onSurface.withValues(alpha: dark ? .0 : .04),
        ],
        stops: const [.72, 1],
        radius: math.max(size.width, size.height) / u * .75,
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, brush);
  }

  @override
  bool shouldRepaint(_CloudBackdrop oldDelegate) =>
      oldDelegate.scheme != scheme || oldDelegate.framed != framed;
}
