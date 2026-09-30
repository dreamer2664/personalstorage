import 'dart:math' as math;
import 'dart:typed_data';

import 'graph_model.dart';

/// Tunables of the force simulation. Defaults are tuned for node radii of 4-20 world units.
class ForceLayoutConfig {
  const ForceLayoutConfig({
    this.repulsion = 1100.0,
    this.springLength = 62.0,
    this.springStiffness = 0.085,
    this.gravity = 0.030,
    this.clusterGravity = 0.05,
    this.velocityDecay = 0.78,
    this.theta = 0.9,
    this.alphaDecay = 0.985,
    this.alphaMin = 0.008,
    this.maxSpeed = 28.0,
    this.collisionPadding = 3.0,
  });

  /// Coulomb-like repulsion constant.
  final double repulsion;

  /// Rest length of an average edge; strong edges rest at ~0.6x, weak ones at ~1.5x.
  final double springLength;
  final double springStiffness;

  /// Pull towards the origin (keeps disconnected components on screen).
  final double gravity;

  /// Pull towards the centroid of the node's cluster (visually groups ideas).
  final double clusterGravity;

  /// Fraction of velocity kept per tick (1 - friction).
  final double velocityDecay;

  /// Barnes-Hut accuracy: larger is faster/rougher.
  final double theta;

  /// Per-tick cooling multiplier of the simulation temperature (alpha).
  final double alphaDecay;
  final double alphaMin;
  final double maxSpeed;
  final double collisionPadding;
}

/// Radius (world units) of a node, shared by layout collision and rendering.
double nodeRadiusFor(GraphNode n) {
  final base = n.type == GraphNodeType.tag ? 5.0 : 4.6;
  final r = base + 2.3 * math.sqrt(n.importance) + 1.25 * math.sqrt(n.degree.toDouble());
  return r.clamp(4.0, 22.0);
}

/// Force-directed graph layout with Barnes-Hut (O(n log n)) repulsion.
///
/// State lives in flat typed arrays, so a tick allocates nothing and 1k nodes comfortably fit a
/// 60 fps frame budget on the UI isolate (see `test/force_layout_test.dart` for the timing).
/// Forces, à la d3-force, are scaled by a cooling temperature [alpha]; interaction (dragging,
/// new data) calls [reheat] to wake the simulation.
class ForceLayout {
  ForceLayout._(this.graph, this.config, this.n, this.edgeCount, this.clusterCount)
      : x = Float64List(n),
        y = Float64List(n),
        vx = Float64List(n),
        vy = Float64List(n),
        _fx = Float64List(n),
        _fy = Float64List(n),
        radius = Float64List(n),
        pinned = Uint8List(n),
        _ea = Int32List(edgeCount),
        _eb = Int32List(edgeCount),
        _ew = Float64List(edgeCount),
        _cluster = Int32List(n),
        _degree = Float64List(n),
        _ccx = Float64List(clusterCount),
        _ccy = Float64List(clusterCount),
        _ccn = Int32List(clusterCount),
        _tree = _QuadTree(n);

  /// Builds a layout for [graph], seeding positions on a deterministic phyllotaxis layout grouped
  /// by cluster so the first frame is already readable.
  factory ForceLayout.fromGraph(KnowledgeGraph graph, {ForceLayoutConfig config = const ForceLayoutConfig(), int seed = 42}) {
    final layout = ForceLayout._(graph, config, graph.nodes.length, graph.edges.length, graph.clusters.length);
    layout._init(seed);
    return layout;
  }

  final KnowledgeGraph graph;
  final ForceLayoutConfig config;
  final int n;
  final int edgeCount;
  final int clusterCount;

  /// Positions and velocities (world units).
  final Float64List x, y, vx, vy;
  final Float64List radius;
  final Uint8List pinned;

  final Float64List _fx, _fy;
  final Int32List _ea, _eb;
  final Float64List _ew;
  final Int32List _cluster;
  final Float64List _degree;
  final Float64List _ccx, _ccy;
  final Int32List _ccn;
  final _QuadTree _tree;

  /// Simulation temperature in `[0, 1]`; the layout is [settled] once it decays below `alphaMin`.
  double alpha = 1.0;

  /// The temperature the simulation relaxes towards (raise while dragging to keep it lively).
  double alphaTarget = 0.0;

  int ticks = 0;
  bool get settled => alpha < config.alphaMin && alphaTarget == 0;

  void _init(int seed) {
    final rnd = math.Random(seed);
    for (var i = 0; i < n; i++) {
      radius[i] = nodeRadiusFor(graph.nodes[i]);
      _cluster[i] = graph.nodes[i].cluster;
      _degree[i] = graph.nodes[i].degree.toDouble();
    }
    for (var e = 0; e < edgeCount; e++) {
      _ea[e] = graph.edges[e].a;
      _eb[e] = graph.edges[e].b;
      _ew[e] = graph.edges[e].weight;
    }
    // Cluster centres on a circle, members on a golden-angle spiral around their centre.
    const golden = 2.399963229728653;
    final spread = 34.0 * math.sqrt(math.max(1, n));
    final slots = clusterCount + 1; // the last slot hosts unclustered nodes
    final counters = List<int>.filled(slots, 0);
    for (var i = 0; i < n; i++) {
      final c = _cluster[i] >= 0 ? _cluster[i] : clusterCount;
      final angleC = c * golden * 2.2;
      final cx = math.cos(angleC) * spread * (c == clusterCount ? 1.15 : math.min(1.0, 0.35 + 0.65 * c / math.max(1, clusterCount)));
      final cy = math.sin(angleC) * spread * (c == clusterCount ? 1.15 : math.min(1.0, 0.35 + 0.65 * c / math.max(1, clusterCount)));
      final k = counters[c]++;
      final r = 11.0 * math.sqrt(k + 0.5);
      final a = k * golden;
      x[i] = cx + math.cos(a) * r + (rnd.nextDouble() - 0.5) * 2;
      y[i] = cy + math.sin(a) * r + (rnd.nextDouble() - 0.5) * 2;
    }
  }

  /// Wakes the simulation after an interaction or data change.
  void reheat([double a = 0.55]) {
    if (a > alpha) alpha = a;
  }

  void setPinned(int i, bool value) => pinned[i] = value ? 1 : 0;

  /// Moves (and pins) node [i] - used while the user drags it.
  void moveNode(int i, double nx, double ny) {
    x[i] = nx;
    y[i] = ny;
    vx[i] = 0;
    vy[i] = 0;
  }

  /// Advances the simulation by [iterations] ticks.
  void step({int iterations = 1}) {
    for (var it = 0; it < iterations; it++) {
      _tick();
    }
  }

  void _tick() {
    if (n == 0) return;
    alpha += (alphaTarget - alpha) * (1 - config.alphaDecay);
    if (settled) return;
    ticks++;
    final a = alpha;

    _fx.fillRange(0, n, 0);
    _fy.fillRange(0, n, 0);

    // Cluster centroids (for cluster gravity).
    if (clusterCount > 0) {
      _ccx.fillRange(0, clusterCount, 0);
      _ccy.fillRange(0, clusterCount, 0);
      _ccn.fillRange(0, clusterCount, 0);
      for (var i = 0; i < n; i++) {
        final c = _cluster[i];
        if (c < 0) continue;
        _ccx[c] += x[i];
        _ccy[c] += y[i];
        _ccn[c]++;
      }
      for (var c = 0; c < clusterCount; c++) {
        if (_ccn[c] > 0) {
          _ccx[c] /= _ccn[c];
          _ccy[c] /= _ccn[c];
        }
      }
    }

    // Repulsion (Barnes-Hut).
    _tree.build(x, y, n);
    final k = config.repulsion * a;
    final theta2 = config.theta * config.theta;
    final collide = 0.3 * math.max(a, 0.25);
    for (var i = 0; i < n; i++) {
      _tree.repel(i, x, y, radius, k, theta2, config.collisionPadding, collide, _fx, _fy);
    }

    // Springs (degree-biased like d3-force so hubs stay put and leaves move).
    final restLen = config.springLength;
    for (var e = 0; e < edgeCount; e++) {
      final ai = _ea[e], bi = _eb[e];
      final w = _ew[e];
      var dx = x[bi] + vx[bi] - x[ai] - vx[ai];
      var dy = y[bi] + vy[bi] - y[ai] - vy[ai];
      var d = math.sqrt(dx * dx + dy * dy);
      if (d < 1e-6) {
        dx = 0.01;
        dy = 0.01;
        d = 0.0142;
      }
      final target = restLen * (1.5 - 0.9 * w) + radius[ai] + radius[bi] - 8;
      final f = (d - target) / d * config.springStiffness * (0.35 + 0.65 * w) * a * 6;
      final bias = _degree[bi] / (_degree[ai] + _degree[bi] + 1e-9);
      _fx[ai] += dx * f * bias;
      _fy[ai] += dy * f * bias;
      _fx[bi] -= dx * f * (1 - bias);
      _fy[bi] -= dy * f * (1 - bias);
    }

    // Gravity towards the origin and the cluster centroid; integrate.
    final g = config.gravity * a;
    final cg = config.clusterGravity * a;
    final decay = config.velocityDecay;
    final vmax = config.maxSpeed;
    for (var i = 0; i < n; i++) {
      var fx = _fx[i] - x[i] * g;
      var fy = _fy[i] - y[i] * g;
      final c = _cluster[i];
      if (c >= 0 && _ccn[c] > 1) {
        fx += (_ccx[c] - x[i]) * cg;
        fy += (_ccy[c] - y[i]) * cg;
      }
      var nvx = (vx[i] + fx) * decay;
      var nvy = (vy[i] + fy) * decay;
      final sp = math.sqrt(nvx * nvx + nvy * nvy);
      if (sp > vmax) {
        nvx *= vmax / sp;
        nvy *= vmax / sp;
      }
      if (pinned[i] != 0) {
        vx[i] = 0;
        vy[i] = 0;
        continue;
      }
      vx[i] = nvx;
      vy[i] = nvy;
      x[i] += nvx;
      y[i] += nvy;
    }
  }

  /// Bounding box of all nodes including their radius: `[minX, minY, maxX, maxY]`.
  List<double> bounds() {
    if (n == 0) return const [0, 0, 0, 0];
    var minX = double.infinity, minY = double.infinity, maxX = -double.infinity, maxY = -double.infinity;
    for (var i = 0; i < n; i++) {
      minX = math.min(minX, x[i] - radius[i]);
      maxX = math.max(maxX, x[i] + radius[i]);
      minY = math.min(minY, y[i] - radius[i]);
      maxY = math.max(maxY, y[i] + radius[i]);
    }
    return [minX, minY, maxX, maxY];
  }

  /// Nearest node whose disc (inflated by [slop] world units) contains the point, or null.
  int? hitTest(double wx, double wy, {double slop = 0}) {
    int? best;
    var bestD = double.infinity;
    for (var i = 0; i < n; i++) {
      final dx = x[i] - wx, dy = y[i] - wy;
      final d2 = dx * dx + dy * dy;
      final r = radius[i] + slop;
      if (d2 <= r * r && d2 < bestD) {
        bestD = d2;
        best = i;
      }
    }
    return best;
  }

  /// Runs the simulation to rest (or [maxTicks]); handy for tests and first-frame layout.
  void settle({int maxTicks = 600}) {
    alpha = math.max(alpha, 1.0);
    for (var t = 0; t < maxTicks && !settled; t++) {
      _tick();
    }
  }
}

/// Barnes-Hut quadtree over flat arrays (no per-node objects -> no GC pressure).
class _QuadTree {
  _QuadTree(int bodies)
      : _cap = math.max(64, bodies * 8 + 64),
        _mass = Float64List(math.max(64, bodies * 8 + 64)),
        _comX = Float64List(math.max(64, bodies * 8 + 64)),
        _comY = Float64List(math.max(64, bodies * 8 + 64)),
        _cx = Float64List(math.max(64, bodies * 8 + 64)),
        _cy = Float64List(math.max(64, bodies * 8 + 64)),
        _half = Float64List(math.max(64, bodies * 8 + 64)),
        _leaf = Int32List(math.max(64, bodies * 8 + 64)),
        _child = Int32List(math.max(64, bodies * 8 + 64) * 4),
        _stack = Int32List(512);

  final int _cap;
  final Float64List _mass, _comX, _comY, _cx, _cy, _half;
  final Int32List _leaf, _child, _stack;
  int _count = 0;
  static const int _maxDepth = 26;

  int _newNode(double cx, double cy, double half) {
    final i = _count++;
    _mass[i] = 0;
    _comX[i] = 0;
    _comY[i] = 0;
    _cx[i] = cx;
    _cy[i] = cy;
    _half[i] = half;
    _leaf[i] = -1;
    final c = i * 4;
    _child[c] = -1;
    _child[c + 1] = -1;
    _child[c + 2] = -1;
    _child[c + 3] = -1;
    return i;
  }

  int _quadrant(int node, double px, double py) => (px >= _cx[node] ? 1 : 0) + (py >= _cy[node] ? 2 : 0);

  int _ensureChild(int node, int q) {
    final slot = node * 4 + q;
    var c = _child[slot];
    if (c >= 0) return c;
    if (_count >= _cap) return -1;
    final h = _half[node] / 2;
    c = _newNode(_cx[node] + ((q & 1) == 1 ? h : -h), _cy[node] + ((q & 2) == 2 ? h : -h), h);
    _child[slot] = c;
    return c;
  }

  void build(Float64List x, Float64List y, int n) {
    var minX = double.infinity, minY = double.infinity, maxX = -double.infinity, maxY = -double.infinity;
    for (var i = 0; i < n; i++) {
      if (x[i] < minX) minX = x[i];
      if (x[i] > maxX) maxX = x[i];
      if (y[i] < minY) minY = y[i];
      if (y[i] > maxY) maxY = y[i];
    }
    _count = 0;
    final half = math.max(math.max(maxX - minX, maxY - minY) / 2, 1.0) + 1;
    _newNode((minX + maxX) / 2, (minY + maxY) / 2, half);
    for (var i = 0; i < n; i++) {
      _insert(i, x, y);
    }
  }

  void _insert(int i, Float64List x, Float64List y) {
    final px = x[i], py = y[i];
    var node = 0;
    var depth = 0;
    while (true) {
      if (_mass[node] == 0) {
        _leaf[node] = i;
        _mass[node] = 1;
        _comX[node] = px;
        _comY[node] = py;
        return;
      }
      if (_leaf[node] >= 0) {
        final j = _leaf[node];
        final coincident = x[j] == px && y[j] == py;
        if (depth >= _maxDepth || coincident || _count + 2 >= _cap) {
          // Bucket leaf: aggregate into this node.
          final m = _mass[node];
          _comX[node] = (_comX[node] * m + px) / (m + 1);
          _comY[node] = (_comY[node] * m + py) / (m + 1);
          _mass[node] = m + 1;
          return;
        }
        _leaf[node] = -1;
        final qj = _quadrant(node, x[j], y[j]);
        final cj = _ensureChild(node, qj);
        _leaf[cj] = j;
        _mass[cj] = 1;
        _comX[cj] = x[j];
        _comY[cj] = y[j];
      }
      final m = _mass[node];
      _comX[node] = (_comX[node] * m + px) / (m + 1);
      _comY[node] = (_comY[node] * m + py) / (m + 1);
      _mass[node] = m + 1;
      final q = _quadrant(node, px, py);
      final next = _ensureChild(node, q);
      if (next < 0) return;
      node = next;
      depth++;
    }
  }

  /// Accumulates the repulsive force on body [i] into [fx]/[fy].
  void repel(
    int i,
    Float64List x,
    Float64List y,
    Float64List radius,
    double k,
    double theta2,
    double pad,
    double collide,
    Float64List fx,
    Float64List fy,
  ) {
    final px = x[i], py = y[i];
    var sp = 0;
    _stack[sp++] = 0;
    var ax = 0.0, ay = 0.0;
    while (sp > 0) {
      final node = _stack[--sp];
      final m = _mass[node];
      if (m == 0) continue;
      final leaf = _leaf[node];
      var dx = _comX[node] - px;
      var dy = _comY[node] - py;
      var d2 = dx * dx + dy * dy;
      if (leaf >= 0) {
        if (leaf == i) continue;
      } else {
        final s = _half[node] * 2;
        if (s * s >= theta2 * d2) {
          final c = node * 4;
          for (var q = 0; q < 4; q++) {
            final ch = _child[c + q];
            if (ch >= 0 && sp < _stack.length) _stack[sp++] = ch;
          }
          continue;
        }
      }
      if (d2 < 0.01) {
        dx = (i.isEven ? 1 : -1) * 0.1;
        dy = 0.1;
        d2 = dx * dx + dy * dy;
      }
      final d = math.sqrt(d2);
      // Softened inverse-square repulsion; leaves also get a short-range collision push.
      var f = k * m / (d2 + 25);
      if (leaf >= 0) {
        final minDist = radius[i] + radius[leaf] + pad;
        if (d < minDist) f += (minDist - d) * collide;
      }
      ax -= dx / d * f;
      ay -= dy / d * f;
    }
    fx[i] += ax;
    fy[i] += ay;
  }
}
