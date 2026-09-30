import 'dart:math' as math;

import 'clustering.dart';
import 'graph_model.dart';

/// Minimal description of a note for graph construction (no DB / UI types).
class GraphNoteInput {
  const GraphNoteInput({
    required this.id,
    required this.label,
    this.categoryId,
    this.importance = 1.0,
    this.tags = const [],
  });

  final String id;
  final String label;
  final String? categoryId;
  final double importance;
  final List<String> tags;
}

class GraphEdgeInput {
  const GraphEdgeInput(this.a, this.b, this.weight, {this.kind = GraphEdgeKind.semantic, this.reason});

  final String a;
  final String b;
  final double weight;
  final GraphEdgeKind kind;
  final String? reason;
}

/// Builds a [KnowledgeGraph] from stored notes and AI-discovered edges.
class GraphBuilder {
  const GraphBuilder._();

  /// [minWeight] hides weak semantic edges (the UI exposes it as a "connection strength"
  /// slider). With [includeTagNodes], tags shared by at least [minTagNotes] notes become hub
  /// nodes - the Obsidian "tags" view.
  static KnowledgeGraph build({
    required List<GraphNoteInput> notes,
    required List<GraphEdgeInput> edges,
    double minWeight = 0.0,
    bool includeTagNodes = false,
    int minTagNotes = 2,
    String Function(String categoryId)? categoryLabel,
  }) {
    final nodes = <GraphNode>[
      for (final n in notes) GraphNode(id: n.id, label: n.label, categoryId: n.categoryId, importance: n.importance),
    ];
    final index = <String, int>{for (var i = 0; i < nodes.length; i++) nodes[i].id: i};

    final best = <(int, int, GraphEdgeKind), GraphEdge>{};
    for (final e in edges) {
      final a = index[e.a], b = index[e.b];
      if (a == null || b == null || a == b) continue;
      if (e.kind == GraphEdgeKind.semantic && e.weight < minWeight) continue;
      final lo = math.min(a, b), hi = math.max(a, b);
      final key = (lo, hi, e.kind);
      final prev = best[key];
      if (prev == null || prev.weight < e.weight) {
        best[key] = GraphEdge(lo, hi, e.weight.clamp(0.01, 1.0), kind: e.kind, reason: e.reason);
      }
    }
    final list = best.values.toList();

    if (includeTagNodes) {
      final byTag = <String, List<int>>{};
      for (var i = 0; i < notes.length; i++) {
        for (final t in notes[i].tags) {
          byTag.putIfAbsent(t, () => []).add(i);
        }
      }
      for (final entry in byTag.entries) {
        if (entry.value.length < minTagNotes) continue;
        final tagIndex = nodes.length;
        nodes.add(
          GraphNode(
            id: 'tag:${entry.key}',
            label: '#${entry.key}',
            type: GraphNodeType.tag,
            importance: 0.8 + 0.3 * math.log(entry.value.length),
          ),
        );
        index['tag:${entry.key}'] = tagIndex;
        for (final n in entry.value) {
          list.add(GraphEdge(n, tagIndex, 0.45, kind: GraphEdgeKind.tag, reason: '#${entry.key}'));
        }
      }
    }

    for (final e in list) {
      nodes[e.a].degree++;
      nodes[e.b].degree++;
    }

    final membership = detectCommunities(nodes.length, list);
    for (var i = 0; i < nodes.length; i++) {
      nodes[i].cluster = membership[i];
    }
    final clusterCount = membership.fold<int>(-1, math.max) + 1;
    final clusters = <GraphCluster>[];
    for (var c = 0; c < clusterCount; c++) {
      final members = [
        for (var i = 0; i < nodes.length; i++)
          if (membership[i] == c) i,
      ];
      clusters.add(_describe(c, members, nodes, notes, index, categoryLabel));
    }
    return KnowledgeGraph(nodes, list, clusters);
  }

  static GraphCluster _describe(
    int c,
    List<int> members,
    List<GraphNode> nodes,
    List<GraphNoteInput> notes,
    Map<String, int> index,
    String Function(String)? categoryLabel,
  ) {
    final tagCount = <String, int>{};
    final catCount = <String, int>{};
    for (final i in members) {
      final node = nodes[i];
      if (node.type == GraphNodeType.tag) {
        tagCount[node.label.substring(1)] = (tagCount[node.label.substring(1)] ?? 0) + 2;
        continue;
      }
      final input = notes[i];
      for (final t in input.tags) {
        tagCount[t] = (tagCount[t] ?? 0) + 1;
      }
      if (input.categoryId != null) catCount[input.categoryId!] = (catCount[input.categoryId!] ?? 0) + 1;
    }
    String? topOf(Map<String, int> m, {int min = 1}) {
      final e = m.entries.where((e) => e.value >= min).toList()
        ..sort((a, b) => b.value != a.value ? b.value.compareTo(a.value) : a.key.compareTo(b.key));
      return e.isEmpty ? null : e.first.key;
    }

    final cat = topOf(catCount);
    final tag = topOf(tagCount, min: 2);
    final label = tag ?? (cat != null ? (categoryLabel?.call(cat) ?? cat) : 'Cluster ${c + 1}');
    return GraphCluster(c, members, label, cat);
  }
}
