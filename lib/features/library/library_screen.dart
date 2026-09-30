import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/navigation.dart';
import '../../app/providers.dart';
import '../../core/design/category_style.dart';
import '../../core/design/glass.dart';
import '../../core/design/labels.dart';
import '../../core/design/theme.dart';
import '../../core/design/toast.dart';
import '../../core/design/tokens.dart';
import '../../core/design/widgets.dart';
import '../../core/util/debouncer.dart';
import '../../domain/models.dart';
import '../../services/note_actions.dart';

import 'package:neural_brain/neural_brain.dart' show Ontology;

import '../../services/sample_data.dart';
import '../../services/search_service.dart';
import '../note/note_detail_screen.dart';
import '../settings/settings_screen.dart';
import 'note_card.dart';

/// Everything you've captured, newest first, with semantic search and category filters.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({required this.bottomInset, super.key});

  final double bottomInset;

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final TextEditingController _query = TextEditingController();
  final Debouncer _debounce = Debouncer(const Duration(milliseconds: 160));
  List<SearchResult>? _results;
  bool _searching = false;
  int _searchGen = 0;
  ToastData? _toast;
  Timer? _toastTimer;
  bool _loadingSamples = false;

  @override
  void dispose() {
    _query.dispose();
    _debounce.dispose();
    _toastTimer?.cancel();
    super.dispose();
  }

  void _onQuery(String text) {
    if (text.trim().isEmpty) {
      _searchGen++;
      setState(() {
        _results = null;
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce.run(() async {
      final services = ref.read(appServicesProvider).value;
      if (services == null) return;
      final gen = ++_searchGen;
      final r = await services.search.search(text);
      if (!mounted || gen != _searchGen) return; // a newer query superseded this one
      setState(() {
        _results = r;
        _searching = false;
      });
    });
  }

  void _open(NoteSummary n) =>
      Navigator.of(context).push(CupertinoPageRoute<void>(builder: (_) => NoteDetailScreen(noteId: n.id)));

  void _flash(ToastData t) {
    _toastTimer?.cancel();
    setState(() => _toast = t);
    _toastTimer = Timer(const Duration(milliseconds: 4200), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  Future<void> _delete(NoteSummary n) async {
    final services = ref.read(appServicesProvider).value;
    if (services == null) return;
    final actions = NoteActions(services);
    await actions.delete(n.id);
    Haptics.medium();
    if (!mounted) return;
    _flash(
      ToastData(
        'Deleted "${n.title}"',
        icon: CupertinoIcons.trash_fill,
        color: context.ps.secondaryLabel,
        actionLabel: 'Undo',
        onAction: () async {
          await actions.undelete(n.id);
          if (mounted) setState(() => _toast = null);
        },
      ),
    );
    if (_results != null) _onQuery(_query.text);
  }

  Future<void> _menu(NoteSummary n) async {
    final choice = await showCupertinoModalPopup<String>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(n.title),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(ctx, 'pin'),
            child: Text(n.pinned ? 'Unpin' : 'Pin to top'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, 'delete'),
            child: const Text('Delete'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
      ),
    );
    final services = ref.read(appServicesProvider).value;
    if (choice == 'pin') await services?.repo.setPinned(n.id, !n.pinned);
    if (choice == 'delete') await _delete(n);
  }

  Future<void> _loadSamples() async {
    final services = ref.read(appServicesProvider).value;
    if (services == null || _loadingSamples) return;
    setState(() => _loadingSamples = true);
    await SampleData.insert(services.capture);
    if (mounted) setState(() => _loadingSamples = false);
  }

  @override
  Widget build(BuildContext context) {
    final ps = context.ps;
    final filter = ref.watch(libraryFilterProvider);
    final summaries = ref.watch(summariesProvider);
    final counts = ref.watch(categoryCountsProvider).value ?? const {};
    final services = ref.watch(appServicesProvider).value;
    final now = DateTime.now();
    final total = counts.values.fold<int>(0, (a, b) => a + b);

    return PsScaffold(
      child: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                PsHeader(
                  title: 'Library',
                  subtitle: total == 0 ? null : '$total ${total == 1 ? 'note' : 'notes'}',
                  trailing: GlassIconButton(
                    icon: CupertinoIcons.gear,
                    semanticLabel: 'Settings',
                    onPressed: () =>
                        Navigator.of(context).push(CupertinoPageRoute<void>(builder: (_) => const SettingsScreen())),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                  child: GlassPanel(
                    radius: 18,
                    blur: false,
                    child: CupertinoTextField.borderless(
                      controller: _query,
                      onChanged: _onQuery,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                      placeholder: 'Search by meaning — try "groceries" or "trip"',
                      placeholderStyle: PsText.body(ps.tertiaryLabel).copyWith(fontSize: 16),
                      style: PsText.body(ps.label).copyWith(fontSize: 16),
                      cursorColor: ps.accent,
                      prefix: Padding(
                        padding: const EdgeInsets.only(left: 14),
                        child: Icon(CupertinoIcons.search, size: 18, color: ps.secondaryLabel),
                      ),
                      suffix: _searching
                          ? const Padding(
                              padding: EdgeInsets.only(right: 14),
                              child: CupertinoActivityIndicator(radius: 8),
                            )
                          : (_query.text.isEmpty
                                ? null
                                : GestureDetector(
                                    onTap: () {
                                      _query.clear();
                                      _onQuery('');
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.only(right: 12),
                                      child: Icon(CupertinoIcons.xmark_circle_fill, size: 18, color: ps.tertiaryLabel),
                                    ),
                                  )),
                    ),
                  ),
                ),
                if (_results == null)
                  _FilterBar(counts: counts, total: total, filter: filter, ontology: services?.ontology),
                Expanded(
                  child: _results != null
                      ? _resultsList(now)
                      : summaries.when(
                          loading: () => const Center(child: CupertinoActivityIndicator()),
                          error: (e, _) => Center(child: Text('$e', style: PsText.body(ps.danger))),
                          data: (list) => _list(list, now, total),
                        ),
                ),
              ],
            ),
            Positioned(
              top: 4,
              left: 24,
              right: 24,
              child: Center(child: GlassToast(data: _toast)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultsList(DateTime now) {
    final list = _results!;
    if (list.isEmpty) {
      return PsEmptyState(
        icon: CupertinoIcons.search,
        title: 'No matches',
        message: 'Nothing in your notes is close to "${_query.text.trim()}".',
      );
    }
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(16, 4, 16, widget.bottomInset + 16),
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) => FadeSlideIn(
        index: i,
        child: NoteCard(
          note: list[i].note,
          now: now,
          reasons: list[i].reasons,
          onTap: () => _open(list[i].note),
          onLongPress: () => _menu(list[i].note),
        ),
      ),
    );
  }

  Widget _list(List<NoteSummary> list, DateTime now, int total) {
    if (list.isEmpty) {
      if (total == 0) {
        return PsEmptyState(
          icon: CupertinoIcons.tray,
          title: 'Nothing captured yet',
          message: 'Notes you capture show up here, automatically organised. No folders, no tagging.',
          action: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PsButton(
                label: _loadingSamples ? 'Adding…' : 'Try with sample notes',
                icon: CupertinoIcons.sparkles,
                onPressed: _loadingSamples ? null : _loadSamples,
              ),
              const SizedBox(height: 10),
              PsButton(
                label: 'Capture a note',
                style: PsButtonStyle.plain,
                onPressed: () => ref.read(selectedTabProvider.notifier).select(0),
              ),
            ],
          ),
        );
      }
      return PsEmptyState(
        icon: CupertinoIcons.line_horizontal_3_decrease,
        title: 'No notes here',
        message: 'Nothing matches this filter yet.',
        action: PsButton(
          label: 'Show all',
          style: PsButtonStyle.tinted,
          onPressed: () => ref.read(libraryFilterProvider.notifier).set(const LibraryFilter()),
        ),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(16, 4, 16, widget.bottomInset + 16),
      itemCount: list.length,
      itemBuilder: (context, i) {
        final n = list[i];
        final card = Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Dismissible(
            key: ValueKey(n.id),
            direction: DismissDirection.endToStart,
            confirmDismiss: (_) async {
              await _delete(n);
              return false; // the stream re-emits without the note
            },
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 22),
              decoration: ShapeDecoration(shape: squircle(PsRadius.card), color: context.ps.danger),
              child: const Icon(CupertinoIcons.trash_fill, color: Color(0xFFFFFFFF)),
            ),
            child: NoteCard(note: n, now: now, onTap: () => _open(n), onLongPress: () => _menu(n)),
          ),
        );
        return i < 10 ? FadeSlideIn(index: i, child: card) : card;
      },
    );
  }
}

class _FilterBar extends ConsumerWidget {
  const _FilterBar({required this.counts, required this.total, required this.filter, required this.ontology});

  final Map<String?, int> counts;
  final int total;
  final LibraryFilter filter;
  final Ontology? ontology;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (total == 0) return const SizedBox.shrink();
    final ps = context.ps;
    final notifier = ref.read(libraryFilterProvider.notifier);
    final entries = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
        children: [
          if (filter.tag != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: PsChip(
                label: '#${filter.tag}',
                color: ps.accent,
                filled: true,
                onRemove: () => notifier.set(LibraryFilter(categoryId: filter.categoryId)),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: PsChip(
              label: 'All · $total',
              color: ps.accent,
              filled: filter.categoryId == null,
              onTap: () {
                Haptics.select();
                notifier.set(LibraryFilter(tag: filter.tag));
              },
            ),
          ),
          for (final e in entries)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: PsChip(
                icon: categoryStyle(e.key).icon,
                label: '${categoryLabel(ontology ?? Ontology.standard, e.key)} · ${e.value}',
                color: categoryStyle(e.key).color,
                filled: filter.categoryId == (e.key ?? '__none'),
                onTap: () {
                  Haptics.select();
                  notifier.set(LibraryFilter(categoryId: filter.categoryId == e.key ? null : e.key, tag: filter.tag));
                },
              ),
            ),
        ],
      ),
    );
  }
}
