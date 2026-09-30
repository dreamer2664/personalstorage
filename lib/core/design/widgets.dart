import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import 'glass.dart';
import 'theme.dart';
import 'tokens.dart';

/// Thin wrapper so haptics can be disabled in one place (Settings) and stubbed in tests.
abstract final class Haptics {
  static bool enabled = true;

  static void light() {
    if (enabled) HapticFeedback.lightImpact();
  }

  static void medium() {
    if (enabled) HapticFeedback.mediumImpact();
  }

  static void select() {
    if (enabled) HapticFeedback.selectionClick();
  }

  static void success() {
    if (enabled) HapticFeedback.heavyImpact();
  }
}

/// Small rounded label with optional icon: the building block of insight chips and tags.
class PsChip extends StatelessWidget {
  const PsChip({
    required this.label,
    this.icon,
    this.color,
    this.filled = false,
    this.onTap,
    this.onRemove,
    this.dense = false,
    super.key,
  });

  final String label;
  final IconData? icon;

  /// Accent of the chip; defaults to the secondary label colour.
  final Color? color;

  /// Solid accent background with white text (used for the active/primary state).
  final bool filled;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final ps = context.ps;
    final c = color ?? ps.secondaryLabel;
    final fg = filled ? const Color(0xFFFFFFFF) : c;
    final bg = filled ? c : c.withValues(alpha: ps.isDark ? 0.22 : 0.13);
    final chip = Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 10, vertical: dense ? 4 : 6),
      decoration: ShapeDecoration(shape: squircle(PsRadius.chip), color: bg),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: dense ? 11 : 13, color: fg), SizedBox(width: dense ? 3 : 5)],
          Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: PsText.chip(fg))),
          if (onRemove != null) ...[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onRemove,
              behavior: HitTestBehavior.opaque,
              child: Icon(CupertinoIcons.xmark, size: 10, color: fg.withValues(alpha: 0.8)),
            ),
          ],
        ],
      ),
    );
    return onTap == null ? chip : PressableScale(onTap: onTap, scale: 0.94, child: chip);
  }
}

enum PsButtonStyle { filled, tinted, plain }

class PsButton extends StatelessWidget {
  const PsButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.style = PsButtonStyle.filled,
    this.color,
    this.expand = false,
    super.key,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final PsButtonStyle style;
  final Color? color;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final ps = context.ps;
    final c = color ?? ps.accent;
    final disabled = onPressed == null;
    final (bg, fg) = switch (style) {
      PsButtonStyle.filled => (c, const Color(0xFFFFFFFF)),
      PsButtonStyle.tinted => (c.withValues(alpha: ps.isDark ? 0.24 : 0.14), c),
      PsButtonStyle.plain => (const Color(0x00000000), c),
    };
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
      decoration: ShapeDecoration(shape: squircle(16), color: disabled ? bg.withValues(alpha: 0.4) : bg),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[Icon(icon, size: 18, color: fg), const SizedBox(width: 8)],
          // Flexible: long labels / large accessibility text wrap instead of overflowing.
          Flexible(child: Text(label, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: PsText.headline(fg))),
        ],
      ),
    );
    return PressableScale(onTap: onPressed == null ? null : () {
      Haptics.light();
      onPressed!();
    }, child: child);
  }
}

/// Fades and slides [child] in; `index` staggers siblings for list entrances.
class FadeSlideIn extends StatelessWidget {
  const FadeSlideIn({required this.child, this.index = 0, this.offset = 14, super.key});

  final Widget child;
  final int index;
  final double offset;

  @override
  Widget build(BuildContext context) {
    final delay = Duration(milliseconds: 35 * index.clamp(0, 8));
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: PsMotion.slow + delay,
      curve: Interval(delay.inMilliseconds / (PsMotion.slow + delay).inMilliseconds, 1, curve: PsMotion.emphasized),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * offset), child: child),
      ),
      child: child,
    );
  }
}

class PsSectionHeader extends StatelessWidget {
  const PsSectionHeader(this.title, {this.trailing, this.padding = const EdgeInsets.fromLTRB(20, 18, 20, 8), super.key});

  final String title;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final ps = context.ps;
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(child: Text(title.toUpperCase(), style: PsText.caption(ps.secondaryLabel).copyWith(letterSpacing: 0.8))),
          ?trailing,
        ],
      ),
    );
  }
}

/// Large-title header used by every tab: title, optional subtitle and trailing actions.
class PsHeader extends StatelessWidget {
  const PsHeader({required this.title, this.subtitle, this.trailing, super.key});

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ps = context.ps;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 16, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (subtitle != null) Text(subtitle!, style: PsText.footnote(ps.secondaryLabel).copyWith(fontWeight: FontWeight.w500)),
                Text(title, style: PsText.largeTitle(ps.label)),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Round glass icon button (navigation bars, overlays).
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({required this.icon, required this.onPressed, this.size = 40, this.color, this.semanticLabel, super.key});

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final ps = context.ps;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: GlassPanel(
        radius: size / 2,
        blur: false,
        shadow: false,
        onTap: onPressed == null
            ? null
            : () {
                Haptics.select();
                onPressed!();
              },
        child: SizedBox(width: size, height: size, child: Icon(icon, size: size * 0.48, color: color ?? ps.label)),
      ),
    );
  }
}

class PsEmptyState extends StatelessWidget {
  const PsEmptyState({required this.icon, required this.title, required this.message, this.action, super.key});

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final ps = context.ps;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GlassPanel(
              radius: 28,
              padding: const EdgeInsets.all(22),
              child: Icon(icon, size: 34, color: ps.accent),
            ),
            const SizedBox(height: 18),
            Text(title, style: PsText.title(ps.label), textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(message, style: PsText.subhead(ps.secondaryLabel), textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}
