import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/design/category_style.dart';
import '../../core/design/glass.dart';
import '../../core/design/theme.dart';
import '../../core/design/tokens.dart';
import '../../core/design/widgets.dart';
import '../../core/util/time_format.dart';
import '../../domain/models.dart';
import '../../services/note_actions.dart';
import '../note/note_detail_screen.dart';

/// Tasks extracted from notes ("call mom tomorrow at 5pm"), grouped by when they are due.
class TasksScreen extends ConsumerWidget {
  const TasksScreen({required this.bottomInset, super.key});

  final double bottomInset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ps = context.ps;
    final tasks = ref.watch(tasksProvider);
    final now = DateTime.now();
    return PsScaffold(
      child: SafeArea(
        bottom: false,
        child: tasks.when(
          loading: () => const Center(child: CupertinoActivityIndicator()),
          error: (e, _) => Center(child: Text('$e', style: PsText.body(ps.danger))),
          data: (all) {
            final groups = _group(all, now);
            final open = all.where((t) => !t.done).length;
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: PsHeader(title: 'Tasks', subtitle: open == 0 ? 'All clear' : '$open open')),
                if (all.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: PsEmptyState(
                      icon: CupertinoIcons.checkmark_seal,
                      title: 'No tasks yet',
                      message: 'Capture something like "remind me to call the dentist on Friday at 10" and it lands here with a deadline.',
                    ),
                  ),
                for (final g in groups)
                  SliverList.list(children: [
                    PsSectionHeader(g.title, trailing: Text('${g.items.length}', style: PsText.caption(g.color ?? ps.secondaryLabel))),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: GlassPanel(
                        blur: false,
                        radius: 20,
                        child: Column(
                          children: [
                            for (var i = 0; i < g.items.length; i++) _TaskRow(task: g.items[i], now: now, showDivider: i < g.items.length - 1),
                          ],
                        ),
                      ),
                    ),
                  ]),
                SliverToBoxAdapter(child: SizedBox(height: bottomInset + 24)),
              ],
            );
          },
        ),
      ),
    );
  }

  List<_Group> _group(List<TaskInfo> all, DateTime now) {
    final overdue = <TaskInfo>[], today = <TaskInfo>[], tomorrow = <TaskInfo>[], week = <TaskInfo>[], later = <TaskInfo>[], none = <TaskInfo>[], done = <TaskInfo>[];
    for (final t in all) {
      if (t.done) {
        done.add(t);
      } else if (t.dueAt == null) {
        none.add(t);
      } else if (t.isOverdue(now)) {
        overdue.add(t);
      } else {
        final d = TimeFormat.daysBetween(now, t.dueAt!);
        (d <= 0 ? today : d == 1 ? tomorrow : d < 7 ? week : later).add(t);
      }
    }
    return [
      if (overdue.isNotEmpty) _Group('Overdue', overdue, const Color(0xFFFF3B30)),
      if (today.isNotEmpty) _Group('Today', today, const Color(0xFF0A84FF)),
      if (tomorrow.isNotEmpty) _Group('Tomorrow', tomorrow, null),
      if (week.isNotEmpty) _Group('This week', week, null),
      if (later.isNotEmpty) _Group('Later', later, null),
      if (none.isNotEmpty) _Group('No date', none, null),
      if (done.isNotEmpty) _Group('Completed', done.take(30).toList(), null),
    ];
  }
}

class _Group {
  _Group(this.title, this.items, this.color);

  final String title;
  final List<TaskInfo> items;
  final Color? color;
}

class _TaskRow extends ConsumerWidget {
  const _TaskRow({required this.task, required this.now, required this.showDivider});

  final TaskInfo task;
  final DateTime now;
  final bool showDivider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ps = context.ps;
    final cat = categoryStyle(task.categoryId);
    final overdue = task.isOverdue(now);
    return Column(
      children: [
        PressableScale(
          scale: 0.99,
          onTap: () => Navigator.of(context).push(CupertinoPageRoute<void>(builder: (_) => NoteDetailScreen(noteId: task.noteId))),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    final services = ref.read(appServicesProvider).value;
                    if (services == null) return;
                    task.done ? Haptics.select() : Haptics.success();
                    NoteActions(services).setTaskDone(task.id, !task.done);
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: AnimatedContainer(
                      duration: PsMotion.base,
                      curve: PsMotion.spring,
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: task.done ? ps.success : const Color(0x00000000),
                        border: Border.all(color: task.done ? ps.success : (overdue ? ps.danger : ps.tertiaryLabel), width: 1.8),
                      ),
                      child: AnimatedOpacity(duration: PsMotion.fast, opacity: task.done ? 1 : 0, child: const Icon(CupertinoIcons.checkmark_alt, size: 16, color: Color(0xFFFFFFFF))),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AnimatedDefaultTextStyle(
                        duration: PsMotion.base,
                        style: PsText.body(task.done ? ps.tertiaryLabel : ps.label).copyWith(decoration: task.done ? TextDecoration.lineThrough : TextDecoration.none),
                        child: Text(task.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(cat.icon, size: 12, color: cat.color),
                          const SizedBox(width: 5),
                          Flexible(child: Text(task.noteTitle ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: PsText.caption(ps.secondaryLabel))),
                          if (task.dueAt != null) ...[
                            Text('  ·  ', style: PsText.caption(ps.tertiaryLabel)),
                            Text(
                              TimeFormat.dueLabel(task.dueAt!, now, hasTime: task.hasTime),
                              style: PsText.caption(overdue ? ps.danger : ps.accent).copyWith(fontWeight: FontWeight.w600),
                            ),
                            if (task.isDeadline) Text(' · deadline', style: PsText.caption(ps.tertiaryLabel)),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (task.priority >= 3) Icon(CupertinoIcons.flag_fill, size: 15, color: ps.danger),
              ],
            ),
          ),
        ),
        if (showDivider) Container(height: 0.5, margin: const EdgeInsets.only(left: 54), color: ps.separator),
      ],
    );
  }
}
