import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neural_brain/neural_brain.dart';

import '../../app/navigation.dart';
import '../../app/providers.dart';
import '../../core/design/category_style.dart';
import '../../core/design/glass.dart';
import '../../core/design/labels.dart';
import '../../core/design/theme.dart';
import '../../core/design/tokens.dart';
import '../../core/design/widgets.dart';
import '../../domain/models.dart';
import '../../services/sample_data.dart';
import '../../services/settings.dart';
import '../note/note_detail_screen.dart';
import 'graph_controller.dart';
import 'graph_painter.dart';

/// Obsidian-style interactive knowledge graph: notes are nodes, AI-discovered relationships are
/// edges, dense regions are clusters. Pinch to zoom, drag to pan, drag a node to rearrange,
/// tap a node to open it, tap a cluster label to see the ideas inside.
class GraphScreen extends ConsumerStatefulWidget {
  const GraphScreen({required this.active, required this.bottomInset, super.key});

  final bool active;
  final double bottomInset;

  @override
  ConsumerState<GraphScreen> createState() => _GraphScreenState();
}

class _GraphScreenState extends ConsumerState<GraphScreen> with SingleTickerProviderStateMixin {
  late final GraphController _c = GraphController(vsync: this);
  Timer? _reloadTimer;
  bool _loaded = false;
  bool _loading = false;
  int? _cluster;
  NoteSummary? _selectedSummary;
  String? _selectedSummaryFor;
  ProviderSubscription<AsyncValue<List<StoredEdge>>>? _edgeSub;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onController);
  }

  @override
  void didUpdateWidget(GraphScreen old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _reload(first: !_loaded);
  }

  @override
  void dispose() {
    _reloadTimer?.cancel();
    _edgeSub?.close();
    _c.removeListener(_onController);
    _c.dispose();
    super.dispose();
  }

  void _onController() {
    // Rebuild the overlay only when the *selection* changes, never per animation frame.
    final sel = _c.selected;
    final id = sel >= 0 ? _c.graph?.nodes[sel].id : null;
    if (id != _selectedSummaryFor) {
      _selectedSummaryFor = id;
      setState(() => _selectedSummary = null);
      if (id != null && _c.graph!.nodes[sel].type == GraphNodeType.note) _loadSummary(id);
    }
  }

  Future<void> _loadSummary(String id) async {
    final services = ref.read(appServicesProvider).value;
    if (services == null) return;
    final list = await services.repo.loadSummaries(ids: {id}, limit: 1);
    if (mounted && _selectedSummaryFor == id) setState(() => _selectedSummary = list.firstOrNull);
  }

  void _scheduleReload() {
    _reloadTimer?.cancel();
    _reloadTimer = Timer(const Duration(milliseconds: 450), () => _reload());
  }

  Future<void> _reload({bool first = false}) async {
    final services = ref.read(appServicesProvider).value;
    if (services == null || _loading) return;
    _loading = true;
    try {
      final s = ref.read(settingsProvider);
      final g = await services.graph.load(
        minWeight: s.edgeThreshold,
        tagHubs: s.showTagHubs,
        categoryLabel: (id) => categoryLabel(services.ontology, id),
      );
      if (!mounted) return;
      _c.setGraph(g, keepPositions: _loaded);
      setState(() => _loaded = true);
      final focus = ref.read(graphFocusProvider);
      if (focus != null) {
        _c.selectById(focus);
        ref.read(graphFocusProvider.notifier).focus(null);
      }
    } finally {
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ps = context.ps;
    final services = ref.watch(appServicesProvider).value;
    final settings = ref.watch(settingsProvider);
    // Reload when notes/edges or graph settings change while visible.
    ref.listen(noteCountProvider, (_, _) => widget.active ? _scheduleReload() : null);
    ref.listen(settingsProvider.select((s) => (s.edgeThreshold, s.showTagHubs)), (_, _) {
      if (widget.active) _scheduleReload();
    });
    ref.listen(graphFocusProvider, (_, focus) {
      if (focus != null && _loaded) {
        _c.selectById(focus);
        ref.read(graphFocusProvider.notifier).focus(null);
      }
    });
    _edgeSub ??= ref.listenManual<AsyncValue<List<StoredEdge>>>(
      edgesProvider,
      (_, _) {
        if (widget.active) _scheduleReload();
      },
    );
    if (widget.active && !_loaded && services != null && !_loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reload(first: true));
    }

    final g = _c.graph;
    final empty = _loaded && (g == null || g.isEmpty);
    return PsScaffold(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (!empty)
            Listener(
              onPointerSignal: (e) {
                if (e is PointerScrollEvent) _c.zoomAt(e.localPosition, e.scrollDelta.dy > 0 ? 0.9 : 1.1);
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onScaleStart: _c.onScaleStart,
                onScaleUpdate: _c.onScaleUpdate,
                onScaleEnd: _c.onScaleEnd,
                onTapUp: (d) {
                  final hit = _c.hitAt(d.localPosition);
                  Haptics.select();
                  if (hit.node != null) {
                    _c.select(hit.node!);
                    setState(() => _cluster = null);
                  } else if (hit.cluster != null) {
                    _c.clearSelection();
                    setState(() => _cluster = hit.cluster);
                  } else {
                    _c.clearSelection();
                    setState(() => _cluster = null);
                  }
                },
                onDoubleTapDown: (d) => _c.zoomAt(d.localPosition, 1.9, animate: true),
                onDoubleTap: () {},
                child: RepaintBoundary(child: CustomPaint(painter: GraphPainter(_c, ps), size: Size.infinite)),
              ),
            ),
          if (empty)
            SafeArea(
              child: PsEmptyState(
                icon: CupertinoIcons.graph_circle,
                title: 'Your graph grows as you capture',
                message: 'Every note becomes a node; related ideas are connected automatically. Capture a few notes, or explore with samples.',
                action: PsButton(
                  label: 'Try with sample notes',
                  icon: CupertinoIcons.sparkles,
                  onPressed: () async {
                    if (services == null) return;
                    await SampleData.insert(services.capture);
                    _scheduleReload();
                  },
                ),
              ),
            ),
          if (!_loaded && !empty) const Center(child: CupertinoActivityIndicator()),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                _TopPill(graph: g, selectedCluster: _cluster, onClear: () => setState(() => _cluster = null)),
                const Spacer(),
                if (_cluster != null && g != null) _ClusterSheet(graph: g, cluster: g.clusters[_cluster!], onClose: () => setState(() => _cluster = null), onOpen: _openNote, onFocus: (i) => _c.selectById(g.nodes[i].id)),
                if (_c.selected >= 0 && g != null && _cluster == null)
                  _SelectionCard(
                    node: g.nodes[_c.selected],
                    summary: _selectedSummary,
                    neighborCount: g.adjacency[_c.selected].length,
                    onOpen: () => _openNote(g.nodes[_c.selected].id),
                    onTagShow: () {
                      ref.read(libraryFilterProvider.notifier).set(LibraryFilter(tag: g.nodes[_c.selected].label.substring(1)));
                      ref.read(selectedTabProvider.notifier).select(1);
                    },
                    onClose: _c.clearSelection,
                  ),
                if (!empty)
                  _Controls(
                    threshold: settings.edgeThreshold,
                    tagHubs: settings.showTagHubs,
                    bottomInset: widget.bottomInset,
                    onFit: () => _c.fit(),
                    onThreshold: (v) => ref.read(settingsProvider.notifier).update(settings.copyWith(edgeThreshold: v)),
                    onTagHubs: () => ref.read(settingsProvider.notifier).update(settings.copyWith(showTagHubs: !settings.showTagHubs)),
                  )
                else
                  SizedBox(height: widget.bottomInset),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openNote(String id) {
    if (id.startsWith('tag:')) return;
    Navigator.of(context).push(CupertinoPageRoute<void>(builder: (_) => NoteDetailScreen(noteId: id)));
  }
}

class _TopPill extends StatelessWidget {
  const _TopPill({required this.graph, required this.selectedCluster, required this.onClear});

  final KnowledgeGraph? graph;
  final int? selectedCluster;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final ps = context.ps;
    final g = graph;
    final notes = g?.nodes.where((n) => n.type == GraphNodeType.note).length ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: GlassPanel(
        radius: 22,
        strong: true,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            Icon(CupertinoIcons.graph_circle_fill, color: ps.accent, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Knowledge graph', style: PsText.headline(ps.label)),
                  Text(
                    g == null ? 'Loading…' : '$notes notes · ${g.edges.length} connections · ${g.clusters.length} clusters',
                    style: PsText.caption(ps.secondaryLabel),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.threshold,
    required this.tagHubs,
    required this.bottomInset,
    required this.onFit,
    required this.onThreshold,
    required this.onTagHubs,
  });

  final double threshold;
  final bool tagHubs;
  final double bottomInset;
  final VoidCallback onFit;
  final ValueChanged<double> onThreshold;
  final VoidCallback onTagHubs;

  @override
  Widget build(BuildContext context) {
    final ps = context.ps;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, bottomInset),
      child: GlassPanel(
        radius: 24,
        strong: true,
        padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
        child: Row(
          children: [
            Icon(CupertinoIcons.slider_horizontal_3, size: 18, color: ps.secondaryLabel),
            const SizedBox(width: 8),
            Text('Links', style: PsText.caption(ps.secondaryLabel)),
            Expanded(
              child: CupertinoSlider(
                value: threshold.clamp(0.26, 0.75),
                min: 0.26,
                max: 0.75,
                onChanged: (v) => onThreshold(double.parse(v.toStringAsFixed(2))),
              ),
            ),
            GlassIconButton(icon: CupertinoIcons.number, size: 38, semanticLabel: 'Toggle tag hubs', color: tagHubs ? ps.accent : ps.secondaryLabel, onPressed: onTagHubs),
            const SizedBox(width: 6),
            GlassIconButton(icon: CupertinoIcons.scope, size: 38, semanticLabel: 'Fit to screen', onPressed: onFit),
          ],
        ),
      ),
    );
  }
}

class _SelectionCard extends StatelessWidget {
  const _SelectionCard({
    required this.node,
    required this.summary,
    required this.neighborCount,
    required this.onOpen,
    required this.onTagShow,
    required this.onClose,
  });

  final GraphNode node;
  final NoteSummary? summary;
  final int neighborCount;
  final VoidCallback onOpen;
  final VoidCallback onTagShow;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final ps = context.ps;
    final isTag = node.type == GraphNodeType.tag;
    final cat = categoryStyle(node.categoryId);
    final s = summary;
    return FadeSlideIn(
      key: ValueKey(node.id),
      offset: 24,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        child: GlassPanel(
          radius: 26,
          strong: true,
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: ShapeDecoration(shape: squircle(11), color: (isTag ? ps.accent : cat.color)),
                    child: Icon(isTag ? CupertinoIcons.number : cat.icon, size: 17, color: const Color(0xFFFFFFFF)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(node.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: PsText.headline(ps.label))),
                  GestureDetector(onTap: onClose, child: Padding(padding: const EdgeInsets.all(6), child: Icon(CupertinoIcons.xmark_circle_fill, color: ps.tertiaryLabel))),
                ],
              ),
              if (s != null && s.snippet.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(s.snippet, maxLines: 2, overflow: TextOverflow.ellipsis, style: PsText.subhead(ps.secondaryLabel)),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        PsChip(dense: true, icon: CupertinoIcons.link, label: '$neighborCount ${neighborCount == 1 ? 'link' : 'links'}', color: ps.secondaryLabel),
                        if (s != null) for (final t in s.tags.take(2)) PsChip(dense: true, label: '#${t.name}', color: cat.color),
                      ],
                    ),
                  ),
                  PsButton(label: isTag ? 'Show notes' : 'Open', icon: isTag ? CupertinoIcons.list_bullet : CupertinoIcons.arrow_right, onPressed: isTag ? onTagShow : onOpen),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClusterSheet extends ConsumerWidget {
  const _ClusterSheet({required this.graph, required this.cluster, required this.onClose, required this.onOpen, required this.onFocus});

  final KnowledgeGraph graph;
  final GraphCluster cluster;
  final VoidCallback onClose;
  final ValueChanged<String> onOpen;
  final ValueChanged<int> onFocus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ps = context.ps;
    final cat = categoryStyle(cluster.categoryId);
    final members = cluster.nodeIndices.where((i) => graph.nodes[i].type == GraphNodeType.note).toList();
    return FadeSlideIn(
      key: ValueKey('cluster-${cluster.index}'),
      offset: 24,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        child: GlassPanel(
          radius: 26,
          strong: true,
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(cat.icon, color: cat.color, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Text('${cluster.label} · ${members.length} ideas', style: PsText.headline(ps.label))),
                  GestureDetector(onTap: onClose, child: Padding(padding: const EdgeInsets.all(6), child: Icon(CupertinoIcons.xmark_circle_fill, color: ps.tertiaryLabel))),
                ],
              ),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 190),
                child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  children: [
                    for (final i in members)
                      PressableScale(
                        scale: 0.99,
                        onTap: () => onOpen(graph.nodes[i].id),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          child: Row(
                            children: [
                              Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: categoryStyle(graph.nodes[i].categoryId).color)),
                              const SizedBox(width: 12),
                              Expanded(child: Text(graph.nodes[i].label, maxLines: 1, overflow: TextOverflow.ellipsis, style: PsText.body(ps.label))),
                              GestureDetector(
                                onTap: () => onFocus(i),
                                child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Icon(CupertinoIcons.scope, size: 16, color: ps.secondaryLabel)),
                              ),
                              Icon(CupertinoIcons.chevron_right, size: 14, color: ps.tertiaryLabel),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
