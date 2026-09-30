import 'package:flutter/cupertino.dart';

import 'glass.dart';
import 'theme.dart';
import 'tokens.dart';
import 'widgets.dart';

/// Content of a transient glass notification.
@immutable
class ToastData {
  const ToastData(
    this.message, {
    this.detail,
    this.icon = CupertinoIcons.checkmark_circle_fill,
    this.color,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final String? detail;
  final IconData icon;
  final Color? color;
  final String? actionLabel;
  final VoidCallback? onAction;
}

/// A floating glass pill that slides in from the top; `null` hides it.
class GlassToast extends StatelessWidget {
  const GlassToast({required this.data, super.key});

  final ToastData? data;

  @override
  Widget build(BuildContext context) {
    final ps = context.ps;
    return IgnorePointer(
      ignoring: data == null,
      child: AnimatedSlide(
        duration: PsMotion.base,
        curve: PsMotion.emphasized,
        offset: data == null ? const Offset(0, -1.4) : Offset.zero,
        child: AnimatedOpacity(
          duration: PsMotion.base,
          opacity: data == null ? 0 : 1,
          child: data == null
              ? const SizedBox(height: 0)
              : GlassPanel(
                  strong: true,
                  radius: 22,
                  padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(data!.icon, size: 22, color: data!.color ?? ps.success),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              data!.message,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: PsText.subhead(ps.label).copyWith(fontWeight: FontWeight.w600),
                            ),
                            if (data!.detail != null)
                              Text(
                                data!.detail!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: PsText.caption(ps.secondaryLabel),
                              ),
                          ],
                        ),
                      ),
                      if (data!.actionLabel != null) ...[
                        const SizedBox(width: 10),
                        PressableScale(
                          onTap: () {
                            Haptics.select();
                            data!.onAction?.call();
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            child: Text(
                              data!.actionLabel!,
                              style: PsText.subhead(ps.accent).copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
