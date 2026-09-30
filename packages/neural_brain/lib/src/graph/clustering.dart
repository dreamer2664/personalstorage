import 'dart:typed_data';

import 'graph_model.dart';

/// Weighted label propagation community detection.
///
/// Near-linear time, no parameters, deterministic (seeded visiting order, ties broken towards the
/// smaller label). Returns, per node, a community index in `0..k-1` ordered by community size
/// (largest first); nodes that end up alone get `-1`.
List<int> detectCommunities(int nodeCount, List<GraphEdge> edges, {int maxIterations = 25, int seed = 7}) {
  final labels = List<int>.generate(nodeCount, (i) => i);
  if (nodeCount == 0) return labels;

  final adj = List.generate(nodeCount, (_) => <(int, double)>[]);
  for (final e in edges) {
    if (e.a == e.b) continue;
    adj[e.a].add((e.b, e.weight));
    adj[e.b].add((e.a, e.weight));
  }

  // Deterministic pseudo-random order (xorshift32), reshuffled every iteration.
  var state = seed == 0 ? 1 : seed;
  int next() {
    state ^= (state << 13) & 0xFFFFFFFF;
    state ^= state >> 17;
    state ^= (state << 5) & 0xFFFFFFFF;
    return state & 0xFFFFFFFF;
  }

  final order = List<int>.generate(nodeCount, (i) => i);
  for (var iter = 0; iter < maxIterations; iter++) {
    for (var i = order.length - 1; i > 0; i--) {
      final j = next() % (i + 1);
      final t = order[i];
      order[i] = order[j];
      order[j] = t;
    }
    var changed = 0;
    for (final v in order) {
      if (adj[v].isEmpty) continue;
      final score = <int, double>{};
      for (final (u, w) in adj[v]) {
        score[labels[u]] = (score[labels[u]] ?? 0) + w;
      }
      var best = labels[v];
      var bestScore = score[best] ?? -1.0;
      score.forEach((label, s) {
        if (s > bestScore + 1e-12 || ((s - bestScore).abs() <= 1e-12 && label < best)) {
          best = label;
          bestScore = s;
        }
      });
      if (best != labels[v]) {
        labels[v] = best;
        changed++;
      }
    }
    if (changed == 0) break;
  }

  // Relabel: communities sorted by size (desc), singletons -> -1.
  final sizes = <int, int>{};
  for (final l in labels) {
    sizes[l] = (sizes[l] ?? 0) + 1;
  }
  final sorted = sizes.entries.where((e) => e.value > 1).toList()
    ..sort((a, b) => b.value != a.value ? b.value.compareTo(a.value) : a.key.compareTo(b.key));
  final remap = <int, int>{for (var i = 0; i < sorted.length; i++) sorted[i].key: i};
  return [for (final l in labels) remap[l] ?? -1];
}

/// Packs `(a, b)` edge pairs into a typed list for the layout engine.
Int32List flattenEdges(List<GraphEdge> edges) {
  final out = Int32List(edges.length * 2);
  for (var i = 0; i < edges.length; i++) {
    out[2 * i] = edges[i].a;
    out[2 * i + 1] = edges[i].b;
  }
  return out;
}
