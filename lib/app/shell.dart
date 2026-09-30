import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/design/glass.dart';
import '../core/design/theme.dart';
import '../core/design/tokens.dart';
import '../core/design/widgets.dart';
import '../core/util/time_format.dart';
import '../features/capture/capture_screen.dart';
import '../features/graph/graph_screen.dart';
import '../features/library/library_screen.dart';
import '../features/note/note_detail_screen.dart';
import '../features/tasks/tasks_screen.dart';
import '../services/launch_actions.dart';
import 'navigation.dart';
import 'providers.dart';

/// Root scaffold: four pages kept alive in an `IndexedStack` and a floating glass tab bar that
/// slides away while the keyboard is open on the Capture tab.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  final GlobalKey<CaptureScreenState> _capture = GlobalKey<CaptureScreenState>();
  static const double barHeight = 64;

  void _handle(LaunchRequest r) {
    final tabs = ref.read(selectedTabProvider.notifier);
    switch (r.type) {
      case LaunchActionType.capture:
        tabs.select(0);
        Navigator.of(context).popUntil((route) => route.isFirst);
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _capture.currentState?.prefill(text: r.text, images: r.imagePaths),
        );
      case LaunchActionType.voice:
        tabs.select(0);
        Navigator.of(context).popUntil((route) => route.isFirst);
        WidgetsBinding.instance.addPostFrameCallback((_) => _capture.currentState?.startVoice());
      case LaunchActionType.openNote:
        if (r.noteId != null) {
          Navigator.of(context).push(CupertinoPageRoute<void>(builder: (_) => NoteDetailScreen(noteId: r.noteId!)));
        }
    }
    ref.read(launchRequestProvider.notifier).consume();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<LaunchRequest?>(launchRequestProvider, (_, r) {
      if (r != null) _handle(r);
    });
    // A request that arrived before the shell existed (cold start from a widget).
    final pending = ref.read(launchRequestProvider);
    if (pending != null) WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? _handle(pending) : null);

    final index = ref.watch(selectedTabProvider);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final bottomInset = barHeight + 24 + math.max(safeBottom, 8);
    final tasks = ref.watch(tasksProvider).value ?? const [];
    final now = DateTime.now();
    final urgent = tasks.where((t) => !t.done && t.dueAt != null && TimeFormat.daysBetween(now, t.dueAt!) <= 0).length;

    return CupertinoPageScaffold(
      backgroundColor: const Color(0x00000000),
      resizeToAvoidBottomInset: false,
      child: Stack(
        children: [
          IndexedStack(
            index: index,
            children: [
              CaptureScreen(key: _capture, active: index == 0, bottomInset: bottomInset),
              LibraryScreen(bottomInset: bottomInset),
              GraphScreen(active: index == 2, bottomInset: bottomInset),
              TasksScreen(bottomInset: bottomInset),
            ],
          ),
          Positioned(
            left: 18,
            right: 18,
            bottom: math.max(safeBottom, 10) + 2,
            child: AnimatedSlide(
              duration: PsMotion.base,
              curve: PsMotion.emphasized,
              offset: keyboard ? const Offset(0, 1.8) : Offset.zero,
              child: AnimatedOpacity(
                duration: PsMotion.fast,
                opacity: keyboard ? 0 : 1,
                child: GlassTabBar(
                  index: index,
                  badge: {3: urgent},
                  onSelect: (i) {
                    Haptics.select();
                    if (i == index && i == 0) _capture.currentState?.focus();
                    ref.read(selectedTabProvider.notifier).select(i);
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Floating glass tab bar with a sliding selection pill.
class GlassTabBar extends StatelessWidget {
  const GlassTabBar({required this.index, required this.onSelect, this.badge = const {}, super.key});

  final int index;
  final ValueChanged<int> onSelect;
  final Map<int, int> badge;

  static const _items = [
    (CupertinoIcons.pencil_circle_fill, 'Capture'),
    (CupertinoIcons.tray_full_fill, 'Library'),
    (CupertinoIcons.graph_circle_fill, 'Graph'),
    (CupertinoIcons.checkmark_circle_fill, 'Tasks'),
  ];

  @override
  Widget build(BuildContext context) {
    final ps = context.ps;
    return GlassPanel(
      radius: PsRadius.bar,
      strong: true,
      padding: const EdgeInsets.all(6),
      child: SizedBox(
        height: _AppShellState.barHeight - 12,
        child: LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth / _items.length;
            return Stack(
              children: [
                AnimatedPositioned(
                  duration: PsMotion.base,
                  curve: PsMotion.emphasized,
                  left: index * w,
                  top: 0,
                  bottom: 0,
                  width: w,
                  child: Container(
                    decoration: ShapeDecoration(
                      shape: squircle(PsRadius.bar - 6),
                      color: ps.accent.withValues(alpha: ps.isDark ? 0.28 : 0.14),
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (var i = 0; i < _items.length; i++)
                      Expanded(
                        child: Semantics(
                          button: true,
                          selected: i == index,
                          label: _items[i].$2,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => onSelect(i),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    AnimatedScale(
                                      duration: PsMotion.base,
                                      curve: PsMotion.spring,
                                      scale: i == index ? 1.12 : 1,
                                      child: Icon(
                                        _items[i].$1,
                                        size: 24,
                                        color: i == index ? ps.accent : ps.secondaryLabel,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _items[i].$2,
                                      style: PsText.caption(i == index ? ps.accent : ps.secondaryLabel)
                                          .copyWith(fontSize: 10.5),
                                    ),
                                  ],
                                ),
                                if ((badge[i] ?? 0) > 0)
                                  Positioned(
                                    top: 2,
                                    right: w / 2 - 26,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: ps.danger,
                                        borderRadius: BorderRadius.circular(9),
                                      ),
                                      child: Text(
                                        '${badge[i]}',
                                        style: PsText.caption(const Color(0xFFFFFFFF))
                                            .copyWith(fontSize: 10, fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
