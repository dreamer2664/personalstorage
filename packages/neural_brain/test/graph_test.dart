import 'dart:math' as math;

import 'package:neural_brain/neural_brain.dart';
import 'package:test/test.dart';

KnowledgeGraph twoCliques({int size = 10, bool bridge = true}) {
  final notes = [
    for (var i = 0; i < size * 2; i++)
      GraphNoteInput(
        id: 'n$i',
        label: 'Note $i',
        categoryId: i < size ? 'a' : 'b',
        tags: [i < size ? 'alpha' : 'beta'],
      ),
  ];
  final edges = <GraphEdgeInput>[];
  for (var c = 0; c < 2; c++) {
    for (var i = 0; i < size; i++) {
      for (var j = i + 1; j < size; j++) {
        edges.add(GraphEdgeInput('n${c * size + i}', 'n${c * size + j}', 0.8));
      }
    }
  }
  if (bridge) edges.add(const GraphEdgeInput('n0', 'n10', 0.35));
  return GraphBuilder.build(notes: notes, edges: edges);
}

void main() {
  group('community detection', () {
    test('separates two cliques joined by a weak bridge', () {
      final g = twoCliques();
      final a = g.nodes.take(10).map((n) => n.cluster).toSet();
      final b = g.nodes.skip(10).map((n) => n.cluster).toSet();
      expect(a, hasLength(1));
      expect(b, hasLength(1));
      expect(a.single, isNot(b.single));
      expect(g.clusters, hasLength(2));
    });

    test('isolated nodes are unclustered; result is deterministic', () {
      final edges = [const GraphEdge(0, 1, 1), const GraphEdge(1, 2, 1)];
      final r1 = detectCommunities(5, edges);
      final r2 = detectCommunities(5, edges);
      expect(r1, r2);
      expect(r1[3], -1);
      expect(r1[4], -1);
      expect(r1.sublist(0, 3).toSet(), hasLength(1));
    });

    test('empty graph', () {
      expect(detectCommunities(0, const []), isEmpty);
    });
  });

  group('graph builder', () {
    test('drops dangling/self edges, dedupes, honours minWeight', () {
      final g = GraphBuilder.build(
        notes: const [
          GraphNoteInput(id: 'a', label: 'A'),
          GraphNoteInput(id: 'b', label: 'B'),
          GraphNoteInput(id: 'c', label: 'C'),
        ],
        edges: const [
          GraphEdgeInput('a', 'b', 0.5),
          GraphEdgeInput('b', 'a', 0.9), // duplicate, stronger wins
          GraphEdgeInput('a', 'a', 1),
          GraphEdgeInput('a', 'zzz', 1),
          GraphEdgeInput('b', 'c', 0.2),
        ],
        minWeight: 0.3,
      );
      expect(g.edges, hasLength(1));
      expect(g.edges.single.weight, 0.9);
      expect(g.nodes[0].degree, 1);
      expect(g.nodes[2].degree, 0);
    });

    test('tag hubs connect notes that share a tag', () {
      final g = GraphBuilder.build(
        notes: const [
          GraphNoteInput(id: 'a', label: 'A', tags: ['lisbon']),
          GraphNoteInput(id: 'b', label: 'B', tags: ['lisbon']),
          GraphNoteInput(id: 'c', label: 'C', tags: ['solo']),
        ],
        edges: const [],
        includeTagNodes: true,
      );
      expect(g.nodes.where((n) => n.type == GraphNodeType.tag).map((n) => n.label), ['#lisbon']);
      expect(g.edges.every((e) => e.kind == GraphEdgeKind.tag), isTrue);
      expect(g.clusters.single.label, 'Lisbon');
    });

    test('cluster labels prefer shared tags, then category', () {
      final g = twoCliques();
      expect(g.clusters.map((c) => c.label).toSet(), {'Alpha', 'Beta'});
    });

    test('neighborsOf walks adjacency', () {
      final g = twoCliques();
      expect(g.neighborsOf(g.indexOf['n0']!).toSet(), contains(g.indexOf['n10']));
    });
  });

  group('force layout', () {
    test('settles without NaNs; linked nodes end up closer than unlinked ones', () {
      final g = twoCliques();
      final l = ForceLayout.fromGraph(g)..settle();
      for (var i = 0; i < l.n; i++) {
        expect(l.x[i].isFinite && l.y[i].isFinite, isTrue);
      }
      double dist(int a, int b) => math.sqrt(math.pow(l.x[a] - l.x[b], 2) + math.pow(l.y[a] - l.y[b], 2));
      var linked = 0.0, linkedN = 0, other = 0.0, otherN = 0;
      final linkedSet = {for (final e in g.edges) (e.a, e.b)};
      for (var a = 0; a < l.n; a++) {
        for (var b = a + 1; b < l.n; b++) {
          if (linkedSet.contains((a, b))) {
            linked += dist(a, b);
            linkedN++;
          } else {
            other += dist(a, b);
            otherN++;
          }
        }
      }
      expect(linked / linkedN, lessThan(other / otherN));
      expect(l.settled, isTrue);
    });

    test('clusters are spatially separated', () {
      final g = twoCliques();
      final l = ForceLayout.fromGraph(g)..settle();
      (double, double) centroid(int from, int to) {
        var cx = 0.0, cy = 0.0;
        for (var i = from; i < to; i++) {
          cx += l.x[i];
          cy += l.y[i];
        }
        return (cx / (to - from), cy / (to - from));
      }

      final a = centroid(0, 10), b = centroid(10, 20);
      final between = math.sqrt(math.pow(a.$1 - b.$1, 2) + math.pow(a.$2 - b.$2, 2));
      var spread = 0.0;
      for (var i = 0; i < 10; i++) {
        spread += math.sqrt(math.pow(l.x[i] - a.$1, 2) + math.pow(l.y[i] - a.$2, 2));
      }
      expect(between, greaterThan(spread / 10), reason: 'centroids should be further apart than the cluster radius');
    });

    test('nodes do not overlap after settling', () {
      final l = ForceLayout.fromGraph(twoCliques(size: 12))..settle();
      var overlaps = 0;
      for (var a = 0; a < l.n; a++) {
        for (var b = a + 1; b < l.n; b++) {
          final d = math.sqrt(math.pow(l.x[a] - l.x[b], 2) + math.pow(l.y[a] - l.y[b], 2));
          if (d < (l.radius[a] + l.radius[b]) * 0.8) overlaps++;
        }
      }
      expect(overlaps, 0);
    });

    test('is deterministic for a given seed', () {
      final a = ForceLayout.fromGraph(twoCliques(), seed: 5)..step(iterations: 50);
      final b = ForceLayout.fromGraph(twoCliques(), seed: 5)..step(iterations: 50);
      expect(a.x, b.x);
      expect(a.y, b.y);
    });

    test('pinned nodes stay put; reheat wakes a settled layout', () {
      final l = ForceLayout.fromGraph(twoCliques())..settle();
      expect(l.settled, isTrue);
      l
        ..moveNode(3, 500, 500)
        ..setPinned(3, true)
        ..reheat();
      expect(l.settled, isFalse);
      l.step(iterations: 30);
      expect(l.x[3], 500);
      expect(l.y[3], 500);
    });

    test('hitTest finds the node under a point, with slop', () {
      final l = ForceLayout.fromGraph(twoCliques())..settle();
      expect(l.hitTest(l.x[4], l.y[4]), 4);
      expect(l.hitTest(l.x[4] + l.radius[4] + 3, l.y[4], slop: 6), isNotNull);
      expect(l.hitTest(1e6, 1e6), isNull);
    });

    test('bounds contain every node', () {
      final l = ForceLayout.fromGraph(twoCliques())..settle();
      final b = l.bounds();
      for (var i = 0; i < l.n; i++) {
        expect(l.x[i], inInclusiveRange(b[0], b[2]));
        expect(l.y[i], inInclusiveRange(b[1], b[3]));
      }
    });

    test('empty and single-node graphs are safe', () {
      ForceLayout.fromGraph(GraphBuilder.build(notes: const [], edges: const [])).step(iterations: 5);
      final one = ForceLayout.fromGraph(
        GraphBuilder.build(
          notes: const [GraphNoteInput(id: 'a', label: 'A')],
          edges: const [],
        ),
      )..settle();
      expect(one.x[0].isFinite, isTrue);
    });

    test('1000 nodes tick well inside a 60 fps budget (Barnes-Hut)', () {
      final rnd = math.Random(1);
      const n = 1000;
      final notes = [for (var i = 0; i < n; i++) GraphNoteInput(id: '$i', label: '$i')];
      final edges = [
        for (var i = 0; i < n * 2; i++)
          GraphEdgeInput('${rnd.nextInt(n)}', '${rnd.nextInt(n)}', 0.3 + rnd.nextDouble() * 0.7),
      ];
      final l = ForceLayout.fromGraph(GraphBuilder.build(notes: notes, edges: edges));
      l.step(iterations: 5); // warm-up
      final sw = Stopwatch()..start();
      l.step(iterations: 50);
      final ms = sw.elapsedMicroseconds / 50 / 1000;
      // ignore: avoid_print
      print('force layout: ${ms.toStringAsFixed(2)} ms / tick for $n nodes, ${l.edgeCount} edges');
      expect(ms, lessThan(16));
    });
  });
}
