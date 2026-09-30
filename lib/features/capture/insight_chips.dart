import 'package:flutter/cupertino.dart';
import 'package:neural_brain/neural_brain.dart';

import '../../core/design/category_style.dart';
import '../../core/design/labels.dart';
import '../../core/design/theme.dart';
import '../../core/design/tokens.dart';
import '../../core/design/widgets.dart';
import '../../core/util/time_format.dart';

/// Live "what the brain understood" chips under the composer: category, reminder, checklist,
/// priority, link and tags. Chips are keyed so only *new* ones animate in while typing.
class InsightChips extends StatelessWidget {
  const InsightChips({
    required this.analysis,
    required this.ontology,
    required this.checklistAccepted,
    required this.onToggleChecklist,
    super.key,
  });

  final NoteAnalysis analysis;
  final Ontology ontology;
  final bool checklistAccepted;
  final VoidCallback onToggleChecklist;

  @override
  Widget build(BuildContext context) {
    final ps = context.ps;
    final a = analysis;
    final now = DateTime.now();
    final chips = <(String, Widget)>[];

    if (a.categoryId != null) {
      final s = categoryStyle(a.categoryId);
      chips.add((
        'cat:${a.categoryId}',
        PsChip(icon: s.icon, label: categoryLabel(ontology, a.categoryId), color: s.color),
      ));
    }
    for (final t in a.actions.take(2)) {
      final due = t.due;
      chips.add((
        'task:${t.title}:${due?.millisecondsSinceEpoch}',
        PsChip(
          icon: due != null ? CupertinoIcons.bell_fill : CupertinoIcons.checkmark_circle,
          label: due != null
              ? '${t.title} · ${TimeFormat.dueLabel(due, now, hasTime: t.hasDueTime)}'
              : 'Task: ${t.title}',
          color: ps.accent,
        ),
      ));
    }
    final checklist = a.checklist;
    final suggestion = a.checklistSuggestion;
    if (checklist != null) {
      chips.add((
        'check',
        PsChip(
          icon: CupertinoIcons.list_bullet,
          label: 'Checklist · ${checklist.items.length} items',
          color: ps.success,
        ),
      ));
    } else if (suggestion != null) {
      chips.add((
        'suggest:$checklistAccepted',
        PsChip(
          icon: checklistAccepted ? CupertinoIcons.checkmark_alt : CupertinoIcons.plus,
          label: checklistAccepted ? 'Checklist · ${suggestion.items.length} items' : 'Make checklist',
          color: ps.success,
          filled: checklistAccepted,
          onTap: onToggleChecklist,
        ),
      ));
    }
    if (a.priority.level.value >= 2) {
      final high = a.priority.level.value >= 3;
      chips.add((
        'prio:${a.priority.level.name}',
        PsChip(
          icon: CupertinoIcons.flag_fill,
          label: high ? 'High priority' : 'Medium priority',
          color: high ? ps.danger : ps.warning,
        ),
      ));
    }
    if (a.entities.urls.isNotEmpty) {
      chips.add(('link', PsChip(icon: CupertinoIcons.link, label: a.entities.urls.first.host, color: ps.accent)));
    }
    for (final t in a.tags.take(3)) {
      chips.add((
        'tag:${t.name}',
        PsChip(label: '#${t.name}', color: t.source == TagSource.user ? ps.accent : ps.secondaryLabel),
      ));
    }

    return AnimatedSize(
      duration: PsMotion.base,
      curve: PsMotion.standard,
      alignment: Alignment.topLeft,
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [for (final (key, chip) in chips) _PopIn(key: ValueKey(key), child: chip)],
      ),
    );
  }
}

class _PopIn extends StatelessWidget {
  const _PopIn({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0.82, end: 1),
    duration: PsMotion.base,
    curve: PsMotion.spring,
    builder: (context, t, child) => Opacity(
      opacity: ((t - 0.82) / 0.18).clamp(0, 1),
      child: Transform.scale(scale: t, child: child),
    ),
    child: child,
  );
}
