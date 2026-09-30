import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:neural_brain/neural_brain.dart';

import '../../core/design/category_style.dart';
import '../../core/design/tokens.dart';
import 'graph_controller.dart';

/// Paints the knowledge graph: cluster halos, weighted edges, category-coloured nodes, and
/// level-of-detail labels. Everything is drawn straight from the layout's typed arrays.
///
/// Performance notes: edges are batched into three `drawRawPoints` calls (by strength) plus one
/// for highlighted edges; nodes off-screen are culled; label `TextPainter`s are laid out once
/// and cached; the same `Paint` objects are reused every frame.
class GraphPainter extends CustomPainter {
  GraphPainter(this.c, this.ps, {this.clusterLabel = _defaultLabel}) : super(repaint: c);

  final GraphController c;
  final PsPalette ps;
  final String Function(GraphCluster) clusterLabel;

  static String _defaultLabel(GraphCluster k) => k.label;

  static final Map<(String, bool, bool), TextPainter> _labelCache = {};
  final Paint _fill = Paint()..isAntiAlias = true;
  final Paint _stroke = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.stroke;
  final Paint _edge = Paint()
    ..isAntiAlias = true
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;

  TextPainter _label(String text, {required bool bold, required bool cluster, required Color color}) {
    final key = (text, bold, cluster);
    final cached = _labelCache[key];
    if (cached != null && cached.text!.style!.color == color) return cached;
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: (cluster ? PsText.headline(color) : PsText.caption(color)).copyWith(
          fontSize: cluster ? 15 : 11.5,
          fontWeight: bold || cluster ? FontWeight.w700 : FontWeight.w500,
          shadows: [Shadow(color: ps.background.withValues(alpha: 0.95), blurRadius: 4), Shadow(color: ps.background, blurRadius: 1)],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: cluster ? 220 : 130);
    if (_labelCache.length > 4000) _labelCache.clear();
    return _labelCache[key] = tp;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final g = c.graph;
    final l = c.layout;
    c.viewport = size;
    c.clusterHitBoxes.clear();
    if (g == null || l == null || l.n == 0) return;

    final s = c.scale;
    final hasSel = c.selected >= 0;
    final worldRect = Rect.fromLTWH(-c.tx / s, -c.ty / s, size.width / s, size.height / s).inflate(40 / s);

    canvas.save();
    canvas.translate(c.tx, c.ty);
    canvas.scale(s);

    _halos(canvas, g, l, s, hasSel);
    _edges(canvas, g, l, s, hasSel, worldRect);
    _nodes(canvas, g, l, s, hasSel, worldRect);
    canvas.restore();

    _labels(canvas, g, l, s, size);
  }

  void _halos(Canvas canvas, KnowledgeGraph g, ForceLayout l, double s, bool hasSel) {
    for (final k in g.clusters) {
      if (k.size < 3) continue;
      var cx = 0.0, cy = 0.0;
      for (final i in k.nodeIndices) {
        cx += l.x[i];
        cy += l.y[i];
      }
      cx /= k.size;
      cy /= k.size;
      var r = 0.0;
      for (final i in k.nodeIndices) {
        r = math.max(r, math.sqrt(math.pow(l.x[i] - cx, 2) + math.pow(l.y[i] - cy, 2)) + l.radius[i]);
      }
      final color = categoryStyle(k.categoryId).color;
      final rect = Rect.fromCircle(center: Offset(cx, cy), radius: r + 26);
      _fill.shader = ui.Gradient.radial(rect.center, rect.width / 2, [color.withValues(alpha: hasSel ? 0.05 : 0.13), color.withValues(alpha: 0)], [0.55, 1]);
      canvas.drawCircle(rect.center, rect.width / 2, _fill);
      _fill.shader = null;
    }
  }

  void _edges(Canvas canvas, KnowledgeGraph g, ForceLayout l, double s, bool hasSel, Rect view) {
    // Three strength buckets + the highlighted set.
    final buckets = [<double>[], <double>[], <double>[]];
    final hot = <double>[];
    for (final e in g.edges) {
      final ax = l.x[e.a], ay = l.y[e.a], bx = l.x[e.b], by = l.y[e.b];
      if (!view.contains(Offset(ax, ay)) && !view.contains(Offset(bx, by))) continue;
      final incident = hasSel && (e.a == c.selected || e.b == c.selected);
      final target = incident ? hot : buckets[e.weight < 0.42 ? 0 : (e.weight < 0.6 ? 1 : 2)];
      target
        ..add(ax)
        ..add(ay)
        ..add(bx)
        ..add(by);
    }
    final base = ps.isDark ? const Color(0xFFFFFFFF) : const Color(0xFF3C3C43);
    final dim = hasSel ? 0.35 : 1.0;
    const alphas = [0.10, 0.18, 0.30];
    const widths = [0.9, 1.3, 1.9];
    for (var i = 0; i < 3; i++) {
      if (buckets[i].isEmpty) continue;
      _edge
        ..color = base.withValues(alpha: alphas[i] * dim)
        ..strokeWidth = math.max(0.5, widths[i] / math.sqrt(s));
      canvas.drawRawPoints(ui.PointMode.lines, Float32List.fromList(buckets[i]), _edge);
    }
    if (hot.isNotEmpty) {
      _edge
        ..color = ps.accent.withValues(alpha: 0.85)
        ..strokeWidth = math.max(1.0, 2.4 / math.sqrt(s));
      canvas.drawRawPoints(ui.PointMode.lines, Float32List.fromList(hot), _edge);
    }
  }

  void _nodes(Canvas canvas, KnowledgeGraph g, ForceLayout l, double s, bool hasSel, Rect view) {
    final hairline = 1.2 / s;
    for (var i = 0; i < g.nodes.length; i++) {
      final x = l.x[i], y = l.y[i], r = l.radius[i];
      if (x < view.left - r || x > view.right + r || y < view.top - r || y > view.bottom + r) continue;
      final node = g.nodes[i];
      final base = node.type == GraphNodeType.tag ? ps.accent : categoryStyle(node.categoryId).color;
      final inFocus = !hasSel || c.neighborhood.contains(i);
      final a = inFocus ? 1.0 : 0.22;
      if (i == c.selected) {
        _fill.color = base.withValues(alpha: 0.22);
        canvas.drawCircle(Offset(x, y), r + 9 / s * 1.4, _fill);
      }
      if (node.type == GraphNodeType.tag) {
        _fill.color = ps.background.withValues(alpha: a);
        canvas.drawCircle(Offset(x, y), r, _fill);
        _stroke
          ..color = base.withValues(alpha: a)
          ..strokeWidth = 2 / s;
        canvas.drawCircle(Offset(x, y), r - 1 / s, _stroke);
      } else {
        _fill.color = base.withValues(alpha: 0.95 * a);
        canvas.drawCircle(Offset(x, y), r, _fill);
        _stroke
          ..color = (ps.isDark ? const Color(0xFFFFFFFF) : const Color(0xFFFFFFFF)).withValues(alpha: (ps.isDark ? 0.25 : 0.85) * a)
          ..strokeWidth = hairline;
        canvas.drawCircle(Offset(x, y), r - hairline / 2, _stroke);
      }
      if (i == c.selected) {
        _stroke
          ..color = ps.label.withValues(alpha: 0.9)
          ..strokeWidth = 2 / s;
        canvas.drawCircle(Offset(x, y), r + 2.5 / s, _stroke);
      }
    }
  }

  void _labels(Canvas canvas, KnowledgeGraph g, ForceLayout l, double s, Size size) {
    final screen = Offset.zero & size;
    // Cluster names when zoomed out: they act as tappable "islands".
    if (s < 1.05) {
      for (final k in g.clusters) {
        if (k.size < 3) continue;
        var cx = 0.0, top = double.infinity;
        for (final i in k.nodeIndices) {
          cx += l.x[i];
          top = math.min(top, l.y[i] - l.radius[i]);
        }
        cx /= k.size;
        final p = c.worldToScreen(cx, top - 16);
        if (!screen.inflate(40).contains(p)) continue;
        final tp = _label(k.label, bold: true, cluster: true, color: categoryStyle(k.categoryId).color);
        final rect = Rect.fromCenter(center: p, width: tp.width + 20, height: tp.height + 10);
        final rr = RRect.fromRectAndRadius(rect, const Radius.circular(14));
        _fill.color = ps.glassFillStrong.withValues(alpha: c.selected >= 0 ? 0.5 : 0.92);
        canvas.drawRRect(rr, _fill);
        _stroke
          ..color = ps.glassBorder
          ..strokeWidth = 0.8;
        canvas.drawRRect(rr, _stroke);
        tp.paint(canvas, rect.topLeft + const Offset(10, 5));
        c.clusterHitBoxes.add((rect.inflate(6), k.index));
      }
    }
    // Node labels: level of detail + greedy collision avoidance. Candidates are placed in
    // priority order (selection, its neighbours, then well-connected / important nodes); a label
    // that would overlap an already placed one is simply skipped, so the picture stays readable
    // at any zoom instead of turning into a wall of text.
    final hasSel = c.selected >= 0;
    final candidates = <(int, double)>[];
    for (var i = 0; i < g.nodes.length; i++) {
      final node = g.nodes[i];
      final important = i == c.selected || (hasSel && c.neighborhood.contains(i));
      if (hasSel && !important) continue; // a selection focuses attention: hide the rest
      final show = important ||
          s >= 1.25 ||
          (s >= 0.85 && (l.radius[i] >= 7.5 || node.type == GraphNodeType.tag)) ||
          (s >= 0.55 && node.degree >= 4 && node.type == GraphNodeType.note);
      if (!show) continue;
      final p = c.worldToScreen(l.x[i], l.y[i]);
      if (!screen.inflate(60).contains(p)) continue;
      final priority = (i == c.selected ? 1e6 : 0) + (important ? 1e5 : 0) + node.degree * 10 + l.radius[i];
      candidates.add((i, priority));
    }
    candidates.sort((a, b) => b.$2.compareTo(a.$2));
    final placed = <Rect>[];
    for (final (i, _) in candidates) {
      if (placed.length >= 140) break;
      final node = g.nodes[i];
      final p = c.worldToScreen(l.x[i], l.y[i]);
      final r = l.radius[i] * s;
      final tp = _label(node.label, bold: i == c.selected, cluster: false, color: ps.label);
      final rect = Rect.fromLTWH(p.dx - tp.width / 2, p.dy + r + 3, tp.width, tp.height);
      final probe = rect.inflate(2);
      var clash = false;
      for (final q in placed) {
        if (q.overlaps(probe)) {
          clash = true;
          break;
        }
      }
      if (clash && i != c.selected) continue;
      placed.add(probe);
      tp.paint(canvas, rect.topLeft);
    }
  }

  @override
  bool shouldRepaint(GraphPainter old) => old.ps != ps || old.c != c;
}
