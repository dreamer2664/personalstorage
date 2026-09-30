import 'package:flutter/cupertino.dart';

import '../../core/design/glass.dart';
import '../../core/design/theme.dart';
import '../../core/design/tokens.dart';
import '../../core/design/widgets.dart';

/// Big round microphone button. While listening it turns red and breathes with the live input
/// level, so the user can see the phone is actually hearing them.
class MicButton extends StatelessWidget {
  const MicButton({required this.listening, required this.level, required this.onTap, super.key});

  final bool listening;
  final double level;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ps = context.ps;
    final color = listening ? ps.danger : ps.accent;
    return Semantics(
      button: true,
      label: listening ? 'Stop dictation' : 'Start voice note',
      child: PressableScale(
        scale: 0.92,
        onTap: () {
          Haptics.medium();
          onTap();
        },
        child: SizedBox(
          width: 72,
          height: 72,
          child: Stack(
            alignment: Alignment.center,
            children: [
              for (final k in const [1.0, 0.6])
                AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOut,
                  width: listening ? 56 + 30 * level * k : 56,
                  height: listening ? 56 + 30 * level * k : 56,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: listening ? 0.12 * k + 0.05 : 0)),
                ),
              AnimatedContainer(
                duration: PsMotion.base,
                curve: PsMotion.standard,
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [color, Color.lerp(color, const Color(0xFF000000), 0.22)!],
                  ),
                  boxShadow: [BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 18, offset: const Offset(0, 8))],
                ),
                child: AnimatedSwitcher(
                  duration: PsMotion.fast,
                  child: Icon(
                    listening ? CupertinoIcons.stop_fill : CupertinoIcons.mic_fill,
                    key: ValueKey(listening),
                    color: const Color(0xFFFFFFFF),
                    size: 24,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Round glass button with an icon (attach photo, save, ...).
class ActionCircle extends StatelessWidget {
  const ActionCircle({required this.icon, required this.onTap, this.label, this.filled = false, this.enabled = true, super.key});

  final IconData icon;
  final VoidCallback onTap;
  final String? label;
  final bool filled;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final ps = context.ps;
    final fg = filled ? const Color(0xFFFFFFFF) : ps.label;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: AnimatedOpacity(
        duration: PsMotion.fast,
        opacity: enabled ? 1 : 0.4,
        child: PressableScale(
          onTap: enabled
              ? () {
                  Haptics.light();
                  onTap();
                }
              : null,
          child: GlassPanel(
            radius: 26,
            blur: false,
            tint: filled ? ps.accent.withValues(alpha: 0.9) : null,
            strong: filled,
            child: SizedBox(width: 52, height: 52, child: Icon(icon, size: 22, color: fg)),
          ),
        ),
      ),
    );
  }
}
