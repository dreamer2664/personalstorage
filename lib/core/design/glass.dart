import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import 'theme.dart';
import 'tokens.dart';

/// A frosted-glass surface: translucent fill, optional backdrop blur, hairline highlight border,
/// soft shadow and continuous corners.
///
/// Backdrop blur is the most expensive effect in Flutter, so it is reserved for *chrome* (bars,
/// composer, sheets, graph overlays). Repeating list items pass `blur: false` and rely on the
/// translucent fill instead - visually near-identical, an order of magnitude cheaper.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    required this.child,
    this.radius = PsRadius.card,
    this.padding,
    this.blur = true,
    this.strong = false,
    this.shadow = true,
    this.tint,
    this.onTap,
    this.onLongPress,
    super.key,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final bool blur;
  final bool strong;
  final bool shadow;

  /// Optional colour wash over the glass (e.g. a category colour at low alpha).
  final Color? tint;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final ps = context.ps;
    final fill = strong ? ps.glassFillStrong : ps.glassFill;
    final shape = squircle(radius, side: BorderSide(color: ps.glassBorder, width: 0.8));
    Widget surface = DecoratedBox(
      decoration: ShapeDecoration(
        shape: shape,
        color: tint == null ? fill : Color.alphaBlend(tint!, fill),
      ),
      child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
    );
    if (blur) {
      surface = ClipPath(
        clipper: ShapeBorderClipper(shape: shape),
        child: BackdropFilter(filter: GlassQuality.filter, child: surface),
      );
    } else {
      surface = ClipPath(clipper: ShapeBorderClipper(shape: shape), child: surface);
    }
    if (shadow) {
      surface = DecoratedBox(
        decoration: ShapeDecoration(
          shape: shape,
          shadows: [
            BoxShadow(color: ps.shadow, blurRadius: 28, offset: const Offset(0, 10)),
            BoxShadow(color: ps.shadow.withValues(alpha: ps.shadow.a * 0.5), blurRadius: 3, offset: const Offset(0, 1)),
          ],
        ),
        child: surface,
      );
    }
    if (onTap != null || onLongPress != null) {
      return PressableScale(onTap: onTap, onLongPress: onLongPress, child: surface);
    }
    return surface;
  }
}

/// Wraps [child] with a subtle scale-down while pressed - the "weight" of every tappable surface.
class PressableScale extends StatefulWidget {
  const PressableScale({
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.97,
    this.behavior = HitTestBehavior.opaque,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final HitTestBehavior behavior;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: widget.behavior,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: PsMotion.fast,
        curve: PsMotion.standard,
        child: widget.child,
      ),
    );
  }
}

/// Soft, slowly drifting colour blobs behind the UI - what makes the glass look like glass.
/// Painted with plain radial gradients (no blur filter), so it costs almost nothing.
class AmbientBackground extends StatefulWidget {
  const AmbientBackground({this.animated = true, super.key});

  final bool animated;

  @override
  State<AmbientBackground> createState() => _AmbientBackgroundState();
}

class _AmbientBackgroundState extends State<AmbientBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 48));

  @override
  void initState() {
    super.initState();
    if (widget.animated) _c.repeat();
  }

  @override
  void didUpdateWidget(AmbientBackground old) {
    super.didUpdateWidget(old);
    if (widget.animated && !_c.isAnimating) _c.repeat();
    if (!widget.animated && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ps = context.ps;
    return RepaintBoundary(
      child: CustomPaint(
        painter: _AmbientPainter(ps, _c),
        size: Size.infinite,
      ),
    );
  }
}

class _AmbientPainter extends CustomPainter {
  _AmbientPainter(this.ps, this.t) : super(repaint: t);

  final PsPalette ps;
  final Animation<double> t;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = ps.background);
    final phase = t.value * 2 * math.pi;
    final r = size.longestSide * 0.62;
    for (var i = 0; i < ps.blobs.length; i++) {
      final a = phase + i * 1.7;
      final cx = size.width * (0.5 + 0.42 * math.cos(a * (1 + i * 0.13) + i));
      final cy = size.height * (0.5 + 0.40 * math.sin(a * (0.8 + i * 0.11) + i * 2));
      final shader = RadialGradient(colors: [ps.blobs[i], ps.blobs[i].withValues(alpha: 0)])
          .createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r));
      canvas.drawCircle(Offset(cx, cy), r, Paint()..shader = shader);
    }
  }

  @override
  bool shouldRepaint(_AmbientPainter old) => old.ps != ps;
}

/// Standard page wrapper: ambient background + content.
class PsScaffold extends StatelessWidget {
  const PsScaffold({required this.child, this.animatedBackground = false, super.key});

  final Widget child;
  final bool animatedBackground;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        AmbientBackground(animated: animatedBackground),
        child,
      ],
    );
  }
}
