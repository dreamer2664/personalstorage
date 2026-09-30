import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:neural_brain/neural_brain.dart';

/// Camera + simulation + selection state of the graph view.
///
/// The painter listens to this object directly (`CustomPainter(repaint: controller)`), so a tick
/// repaints the canvas without rebuilding any widget - the key to smooth 60 fps animation.
/// A [Ticker] runs only while something is moving (layout cooling, inertia, camera moves), and
/// stops itself when everything has settled, so an idle graph costs no battery.
class GraphController extends ChangeNotifier {
  GraphController({required TickerProvider vsync}) {
    _ticker = vsync.createTicker(_onTick);
  }

  late final Ticker _ticker;

  KnowledgeGraph? graph;
  ForceLayout? layout;

  // Camera: screen = world * scale + (tx, ty).
  double scale = 1, tx = 0, ty = 0;
  double _targetScale = 1, _targetTx = 0, _targetTy = 0;
  bool _cameraAnimating = false;
  Size viewport = Size.zero;

  /// Selected node index (or -1) and its neighbourhood for highlighting.
  int selected = -1;
  Set<int> neighborhood = const {};

  /// Node being dragged (or -1).
  int dragging = -1;

  /// Cluster label hit boxes in *screen* space, refreshed by the painter each frame.
  final List<(Rect, int)> clusterHitBoxes = [];

  Offset _inertia = Offset.zero; // screen px per second
  Duration _last = Duration.zero;
  double _startScale = 1;
  bool _camera = false;

  static const double minScale = 0.12, maxScale = 6;

  // ───────────────────────────── data ─────────────────────────────

  /// Installs [g], reusing positions of nodes that already existed so a refresh doesn't shake.
  void setGraph(KnowledgeGraph g, {bool keepPositions = true}) {
    final old = layout;
    final oldGraph = graph;
    graph = g;
    final next = ForceLayout.fromGraph(g);
    if (keepPositions && old != null && oldGraph != null) {
      var kept = 0;
      for (var i = 0; i < g.nodes.length; i++) {
        final j = oldGraph.indexOf[g.nodes[i].id];
        if (j != null) {
          next.x[i] = old.x[j];
          next.y[i] = old.y[j];
          kept++;
        }
      }
      if (kept > 0) {
        next.alpha = 0.35;
      }
    }
    layout = next;
    if (!keepPositions || old == null) {
      next.step(iterations: 70); // pre-warm: the first visible frame is already organised
    }
    if (selected >= g.nodes.length ||
        (oldGraph != null &&
            selected >= 0 &&
            oldGraph.nodes[selected].id != (selected < g.nodes.length ? g.nodes[selected].id : ''))) {
      clearSelection(notify: false);
    }
    if (old == null) fit(animate: false);
    _wake();
    notifyListeners();
  }

  // ───────────────────────────── camera ─────────────────────────────

  Offset worldToScreen(double x, double y) => Offset(x * scale + tx, y * scale + ty);
  Offset screenToWorld(Offset p) => Offset((p.dx - tx) / scale, (p.dy - ty) / scale);

  /// Frames the whole graph (or [nodeIndex] when given) in the viewport.
  void fit({bool animate = true, int? nodeIndex, double padding = 56}) {
    final l = layout;
    if (l == null || viewport.isEmpty || l.n == 0) return;
    double s, cx, cy;
    if (nodeIndex != null) {
      s = math.max(scale, 1.4).clamp(minScale, maxScale);
      cx = l.x[nodeIndex];
      cy = l.y[nodeIndex];
    } else {
      final b = l.bounds();
      final w = math.max(b[2] - b[0], 60.0), h = math.max(b[3] - b[1], 60.0);
      s = math.min((viewport.width - 2 * padding) / w, (viewport.height - 2 * padding - 120) / h).clamp(minScale, 1.6);
      cx = (b[0] + b[2]) / 2;
      cy = (b[1] + b[3]) / 2;
    }
    _targetScale = s;
    _targetTx = viewport.width / 2 - cx * s;
    _targetTy = viewport.height / 2 - cy * s - (nodeIndex != null ? 70 : 20);
    if (animate) {
      _cameraAnimating = true;
      _wake();
    } else {
      scale = _targetScale;
      tx = _targetTx;
      ty = _targetTy;
      notifyListeners();
    }
  }

  void zoomAt(Offset focal, double factor, {bool animate = false}) {
    final newScale = (scale * factor).clamp(minScale, maxScale);
    final world = screenToWorld(focal);
    final ntx = focal.dx - world.dx * newScale;
    final nty = focal.dy - world.dy * newScale;
    if (animate) {
      _targetScale = newScale;
      _targetTx = ntx;
      _targetTy = nty;
      _cameraAnimating = true;
      _wake();
    } else {
      scale = newScale;
      tx = ntx;
      ty = nty;
      _cameraAnimating = false;
      notifyListeners();
    }
  }

  // ───────────────────────────── gestures ─────────────────────────────

  void onScaleStart(ScaleStartDetails d) {
    _inertia = Offset.zero;
    _cameraAnimating = false;
    _startScale = scale;
    final l = layout;
    _camera = true;
    if (l != null && d.pointerCount == 1) {
      final w = screenToWorld(d.localFocalPoint);
      final hit = l.hitTest(w.dx, w.dy, slop: 14 / scale);
      if (hit != null) {
        dragging = hit;
        _camera = false;
        l.setPinned(hit, true);
        l.alphaTarget = 0.22; // keep the simulation alive so neighbours follow the finger
        l.reheat(0.4);
        _wake();
      }
    }
  }

  void onScaleUpdate(ScaleUpdateDetails d) {
    final l = layout;
    if (l == null) return;
    if (dragging >= 0 && d.pointerCount == 1) {
      final w = screenToWorld(d.localFocalPoint);
      l.moveNode(dragging, w.dx, w.dy);
      notifyListeners();
      return;
    }
    if (dragging >= 0) {
      // A second finger arrived: release the node and switch to camera mode.
      _releaseDrag();
      _camera = true;
      _startScale = scale;
    }
    // Pinch-zoom around the focal point + pan.
    final newScale = (_startScale * d.scale).clamp(minScale, maxScale);
    final focal = d.localFocalPoint;
    final worldBefore = screenToWorld(focal - d.focalPointDelta);
    scale = newScale;
    tx = focal.dx - worldBefore.dx * newScale;
    ty = focal.dy - worldBefore.dy * newScale;
    notifyListeners();
  }

  void onScaleEnd(ScaleEndDetails d) {
    if (dragging >= 0) {
      _releaseDrag();
      return;
    }
    if (_camera) {
      _inertia = d.velocity.pixelsPerSecond;
      if (_inertia.distance > 80) _wake();
    }
  }

  void _releaseDrag() {
    final l = layout;
    if (l != null && dragging >= 0) {
      l.setPinned(dragging, false);
      l.alphaTarget = 0;
    }
    dragging = -1;
  }

  /// Returns the tapped node index, cluster index (as negative `-(c+2)`), or null.
  ({int? node, int? cluster}) hitAt(Offset screen) {
    final l = layout;
    if (l != null) {
      final w = screenToWorld(screen);
      final hit = l.hitTest(w.dx, w.dy, slop: 12 / scale);
      if (hit != null) return (node: hit, cluster: null);
    }
    for (final (rect, cluster) in clusterHitBoxes) {
      if (rect.contains(screen)) return (node: null, cluster: cluster);
    }
    return (node: null, cluster: null);
  }

  void select(int index) {
    final g = graph;
    if (g == null || index < 0 || index >= g.nodes.length) return;
    selected = index;
    neighborhood = {index, ...g.neighborsOf(index)};
    notifyListeners();
  }

  void selectById(String id, {bool focus = true}) {
    final i = graph?.indexOf[id];
    if (i == null) return;
    select(i);
    if (focus) fit(nodeIndex: i);
  }

  void clearSelection({bool notify = true}) {
    selected = -1;
    neighborhood = const {};
    if (notify) notifyListeners();
  }

  // ───────────────────────────── ticking ─────────────────────────────

  void _wake() {
    if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void _onTick(Duration elapsed) {
    final dt = _last == Duration.zero ? 1 / 60 : math.min(0.05, (elapsed - _last).inMicroseconds / 1e6);
    _last = elapsed;
    var active = false;

    final l = layout;
    if (l != null && !l.settled) {
      l.step();
      active = true;
    }
    if (_inertia.distance > 12) {
      tx += _inertia.dx * dt;
      ty += _inertia.dy * dt;
      _inertia *= math.pow(0.0015, dt).toDouble(); // exponential friction
      active = true;
    } else {
      _inertia = Offset.zero;
    }
    if (_cameraAnimating) {
      final k = 1 - math.exp(-dt * 9);
      scale += (_targetScale - scale) * k;
      tx += (_targetTx - tx) * k;
      ty += (_targetTy - ty) * k;
      if ((_targetScale - scale).abs() < 0.002 && (_targetTx - tx).abs() < 0.3 && (_targetTy - ty).abs() < 0.3) {
        scale = _targetScale;
        tx = _targetTx;
        ty = _targetTy;
        _cameraAnimating = false;
      } else {
        active = true;
      }
    }
    if (dragging >= 0) active = true;
    notifyListeners();
    if (!active) {
      _ticker.stop();
      _last = Duration.zero;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}
