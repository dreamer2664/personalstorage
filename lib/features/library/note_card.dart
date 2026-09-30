import 'package:flutter/cupertino.dart';
import 'package:neural_brain/neural_brain.dart';

import '../../core/design/category_style.dart';
import '../../core/design/collage.dart';
import '../../core/design/glass.dart';
import '../../core/design/theme.dart';
import '../../core/design/tokens.dart';
import '../../core/design/widgets.dart';
import '../../core/util/time_format.dart';
import '../../domain/models.dart';

/// A note in a list: category badge, title, snippet, tags, due date, checklist progress and
/// a photo collage. Uses a translucent fill *without* backdrop blur (cheap in long lists).
class NoteCard extends StatelessWidget {
  const NoteCard({
    required this.note,
    required this.now,
    required this.onTap,
    this.reasons = const [],
    this.onLongPress,
    this.compact = false,
    super.key,
  });

  final NoteSummary note;
  final DateTime now;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// Why a search matched ("Concept: Groceries", "Similar meaning").
  final List<String> reasons;

  /// Tighter variant for horizontal strips: fewer chips, single-line title.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ps = context.ps;
    final cat = categoryStyle(note.categoryId);
    final overdue = note.nextDue != null && note.nextDue!.isBefore(now) && note.openTasks > 0;
    return Semantics(
      button: true,
      label: '${note.title}. ${note.snippet}',
      child: GlassPanel(
        blur: false,
        radius: PsRadius.card,
        onTap: onTap,
        onLongPress: onLongPress,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Badge(style: cat, kind: note.kind),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (note.pinned) ...[
                            Icon(CupertinoIcons.pin_fill, size: 12, color: ps.warning),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: Text(
                              note.title,
                              maxLines: compact ? 1 : 2,
                              overflow: TextOverflow.ellipsis,
                              style: PsText.headline(ps.label),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(TimeFormat.ago(note.createdAt, now), style: PsText.caption(ps.tertiaryLabel)),
                        ],
                      ),
                      if (note.snippet.isNotEmpty && note.kind != NoteKind.checklist) ...[
                        const SizedBox(height: 3),
                        Text(
                          note.snippet,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: PsText.subhead(ps.secondaryLabel),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (note.imageUris.isNotEmpty) ...[
              const SizedBox(height: 10),
              PhotoCollage(paths: note.imageUris.take(4).toList(), height: 92, radius: 14, cacheWidth: 320),
            ],
            if (note.kind == NoteKind.link && note.linkHost != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(CupertinoIcons.link, size: 13, color: ps.accent),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      note.linkHost!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PsText.footnote(ps.accent),
                    ),
                  ),
                ],
              ),
            ],
            if (_hasMeta) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (note.nextDue != null)
                    PsChip(
                      dense: true,
                      icon: overdue ? CupertinoIcons.exclamationmark_circle_fill : CupertinoIcons.bell_fill,
                      label: TimeFormat.dueLabel(note.nextDue!, now, hasTime: note.nextDueHasTime),
                      color: overdue ? ps.danger : ps.accent,
                    ),
                  if (note.checklistTotal > 0)
                    PsChip(
                      dense: true,
                      icon: CupertinoIcons.checkmark_circle,
                      label: '${note.checklistDone}/${note.checklistTotal}',
                      color: note.checklistDone == note.checklistTotal ? ps.success : ps.secondaryLabel,
                    ),
                  if (note.priority >= 2)
                    PsChip(
                      dense: true,
                      icon: CupertinoIcons.flag_fill,
                      label: note.priority >= 3 ? 'High' : 'Medium',
                      color: note.priority >= 3 ? ps.danger : ps.warning,
                    ),
                  for (final t in note.tags.take(compact ? 2 : 3))
                    PsChip(dense: true, label: '#${t.name}', color: t.isUser ? ps.accent : cat.color),
                ],
              ),
            ],
            if (reasons.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(CupertinoIcons.sparkles, size: 12, color: ps.accent),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      reasons.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PsText.caption(ps.accent),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool get _hasMeta => note.nextDue != null || note.checklistTotal > 0 || note.tags.isNotEmpty || note.priority >= 2;
}

class _Badge extends StatelessWidget {
  const _Badge({required this.style, required this.kind});

  final CategoryStyle style;
  final NoteKind kind;

  @override
  Widget build(BuildContext context) {
    final icon = switch (kind) {
      NoteKind.checklist => CupertinoIcons.list_bullet,
      NoteKind.link => CupertinoIcons.link,
      NoteKind.image => CupertinoIcons.photo_fill,
      NoteKind.text => style.icon,
    };
    return Container(
      width: 38,
      height: 38,
      decoration: ShapeDecoration(
        shape: squircle(12),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [style.color, Color.lerp(style.color, const Color(0xFF000000), 0.18)!],
        ),
        shadows: [BoxShadow(color: style.color.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Icon(icon, size: 19, color: const Color(0xFFFFFFFF)),
    );
  }
}
