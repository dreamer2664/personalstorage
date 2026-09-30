/// Kind of a graph node.
enum GraphNodeType { note, tag }

/// Why two nodes are connected.
enum GraphEdgeKind {
  /// AI-detected semantic relatedness between two notes.
  semantic,

  /// A note carries a tag (note -> tag hub).
  tag,

  /// Explicit `[[wikilink]]` reference.
  link,
}

class GraphNode {
  GraphNode({
    required this.id,
    required this.label,
    this.type = GraphNodeType.note,
    this.categoryId,
    this.importance = 1.0,
  });

  final String id;
  final String label;
  final GraphNodeType type;
  final String? categoryId;

  /// Visual weight (priority / pinned / degree), `>= 0`. Drives node radius.
  double importance;

  /// Index of the cluster this node belongs to, or -1 when unclustered. Filled by the builder.
  int cluster = -1;

  /// Number of incident edges. Filled by the builder.
  int degree = 0;
}

class GraphEdge {
  const GraphEdge(this.a, this.b, this.weight, {this.kind = GraphEdgeKind.semantic, this.reason});

  /// Node indices (into [KnowledgeGraph.nodes]).
  final int a;
  final int b;

  /// Strength in `(0, 1]`; stronger edges pull nodes closer together.
  final double weight;
  final GraphEdgeKind kind;
  final String? reason;
}

/// A group of densely connected nodes.
class GraphCluster {
  GraphCluster(this.index, this.nodeIndices, this.label, this.categoryId);

  final int index;
  final List<int> nodeIndices;
  final String label;
  final String? categoryId;
  int get size => nodeIndices.length;
}

/// Immutable snapshot of the knowledge graph handed to the layout engine and the painter.
class KnowledgeGraph {
  KnowledgeGraph(this.nodes, this.edges, this.clusters)
    : indexOf = {for (var i = 0; i < nodes.length; i++) nodes[i].id: i},
      adjacency = List.generate(nodes.length, (_) => <int>[]) {
    for (var e = 0; e < edges.length; e++) {
      adjacency[edges[e].a].add(e);
      adjacency[edges[e].b].add(e);
    }
  }

  final List<GraphNode> nodes;
  final List<GraphEdge> edges;
  final List<GraphCluster> clusters;
  final Map<String, int> indexOf;

  /// For each node, indices into [edges].
  final List<List<int>> adjacency;

  bool get isEmpty => nodes.isEmpty;

  /// Indices of the nodes directly connected to [node].
  Iterable<int> neighborsOf(int node) sync* {
    for (final e in adjacency[node]) {
      final edge = edges[e];
      yield edge.a == node ? edge.b : edge.a;
    }
  }
}
