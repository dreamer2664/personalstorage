import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neural_brain/neural_brain.dart';
import 'package:personalstorage/core/design/tokens.dart';
import 'package:personalstorage/features/graph/graph_controller.dart';
import 'package:personalstorage/features/graph/graph_painter.dart';

KnowledgeGraph _graph({int n = 30}) {
  final notes = [
    for (var i = 0; i < n; i++)
      GraphNoteInput(id: 'n$i', label: 'A fairly long note title number $i', categoryId: const ['travel', 'shopping', 'tech'][i % 3], tags: ['t${i % 4}']),
  ];
  final edges = [
    for (var i = 0; i < n - 1; i++) GraphEdgeInput('n$i', 'n${i + 1}', 0.5 + (i % 5) * 0.08),
    for (var i = 0; i + 5 < n; i += 3) GraphEdgeInput('n$i', 'n${i + 5}', 0.4),
  ];
  return GraphBuilder.build(notes: notes, edges: edges);
}

/// Runs [body] with a controller and always disposes it *inside* the test: Flutter checks for
/// running tickers before tear-down callbacks fire.
Future<void> withController(Future<void> Function(GraphController c) body, {int n = 30, Size viewport = const Size(390, 844)}) async {
  final c = GraphController(vsync: const TestVSync())..viewport = viewport;
  try {
    c.setGraph(_graph(n: n));
    await body(c);
  } finally {
    c.dispose();
  }
}

void main() {
  group('GraphController', () {
    testWidgets('installs a graph, pre-warms the layout and frames it in the viewport', (t) => withController((c) async {
      expect(c.layout, isNotNull);
      expect(c.layout!.ticks, greaterThan(10), reason: 'pre-warmed so the first frame is organised');
      for (var i = 0; i < c.layout!.n; i++) {
        final p = c.worldToScreen(c.layout!.x[i], c.layout!.y[i]);
        expect(p.dx, inInclusiveRange(-1, 391), reason: 'node $i x');
        expect(p.dy, inInclusiveRange(-1, 845), reason: 'node $i y');
      }
    }));

    testWidgets('screen/world transforms are inverses; zoomAt keeps the focal point fixed', (t) => withController((c) async {
      const focal = Offset(120, 300);
      final before = c.screenToWorld(focal);
      c.zoomAt(focal, 2.0);
      final after = c.screenToWorld(focal);
      expect(after.dx, closeTo(before.dx, 1e-6));
      expect(after.dy, closeTo(before.dy, 1e-6));
      final w = c.screenToWorld(c.worldToScreen(12.5, -7.25));
      expect(w.dx, closeTo(12.5, 1e-9));
      expect(w.dy, closeTo(-7.25, 1e-9));
    }));

    testWidgets('zoom is clamped', (t) => withController((c) async {
      for (var i = 0; i < 30; i++) {
        c.zoomAt(const Offset(200, 400), 2);
      }
      expect(c.scale, GraphController.maxScale);
      for (var i = 0; i < 60; i++) {
        c.zoomAt(const Offset(200, 400), 0.5);
      }
      expect(c.scale, GraphController.minScale);
    }));

    testWidgets('tapping a node selects it and highlights its neighbourhood', (t) => withController((c) async {
      final l = c.layout!;
      final screen = c.worldToScreen(l.x[4], l.y[4]);
      final hit = c.hitAt(screen);
      expect(hit.node, 4);
      c.select(hit.node!);
      expect(c.selected, 4);
      expect(c.neighborhood, contains(4));
      expect(c.neighborhood, containsAll(c.graph!.neighborsOf(4)));
      c.clearSelection();
      expect(c.selected, -1);
      expect(c.hitAt(const Offset(-500, -500)).node, isNull);
    }));

    testWidgets('dragging a node moves and pins it, then releases it', (t) => withController((c) async {
      final l = c.layout!;
      final start = c.worldToScreen(l.x[2], l.y[2]);
      c.onScaleStart(ScaleStartDetails(focalPoint: start, localFocalPoint: start, pointerCount: 1));
      expect(c.dragging, 2);
      expect(l.pinned[2], 1);
      final target = start + const Offset(60, 40);
      c.onScaleUpdate(ScaleUpdateDetails(focalPoint: target, localFocalPoint: target, pointerCount: 1));
      final w = c.screenToWorld(target);
      expect(l.x[2], closeTo(w.dx, 1e-6));
      c.onScaleEnd(ScaleEndDetails());
      expect(c.dragging, -1);
      expect(l.pinned[2], 0);
    }));

    testWidgets('pinch gestures change the zoom, not the nodes', (t) => withController((c) async {
      final l = c.layout!;
      final x0 = l.x[0];
      const focal = Offset(1, 1); // empty space
      c.onScaleStart(ScaleStartDetails(focalPoint: focal, localFocalPoint: focal, pointerCount: 2));
      final s0 = c.scale;
      c.onScaleUpdate(ScaleUpdateDetails(focalPoint: focal, localFocalPoint: focal, scale: 1.8, pointerCount: 2));
      expect(c.scale, closeTo(s0 * 1.8, 1e-6));
      expect(l.x[0], x0);
    }));

    testWidgets('re-installing a graph keeps positions of existing nodes (no shake on refresh)', (t) => withController((c) async {
      final x5 = c.layout!.x[5];
      final y5 = c.layout!.y[5];
      c.setGraph(_graph(n: 31));
      expect(c.layout!.x[5], closeTo(x5, 1e-9));
      expect(c.layout!.y[5], closeTo(y5, 1e-9));
    }));

    testWidgets('selectById frames the node', (t) => withController((c) async {
      c.selectById('n7');
      expect(c.selected, 7);
    }));
  });

  group('GraphPainter', () {
    Future<void> paintOnce(GraphController c, PsPalette ps) async {
      final recorder = ui.PictureRecorder();
      GraphPainter(c, ps).paint(Canvas(recorder), const Size(390, 844));
      recorder.endRecording().dispose();
    }

    testWidgets('paints overview, selection and zoomed states in both themes without errors', (t) => withController((c) async {
      for (final ps in [PsPalette.light, PsPalette.dark]) {
        await paintOnce(c, ps);
        c.select(10);
        await paintOnce(c, ps);
        c.zoomAt(const Offset(195, 420), 3);
        await paintOnce(c, ps);
        c.clearSelection();
        c.fit(animate: false);
      }
      expect(c.clusterHitBoxes.length, lessThanOrEqualTo(c.graph!.clusters.length));
    }, n: 60));

    testWidgets('renders through CustomPaint at high zoom (label collision avoidance) without errors', (t) async {
      final c = GraphController(vsync: const TestVSync())..viewport = const Size(390, 844);
      try {
        c.setGraph(_graph(n: 50));
        c.zoomAt(const Offset(195, 420), 2.5);
        await t.pumpWidget(Directionality(textDirection: TextDirection.ltr, child: CustomPaint(painter: GraphPainter(c, PsPalette.light), size: const Size(390, 844))));
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      } finally {
        c.dispose();
      }
    });

    testWidgets('an empty graph paints nothing and does not throw', (t) async {
      final c = GraphController(vsync: const TestVSync())..viewport = const Size(390, 844);
      try {
        c.setGraph(GraphBuilder.build(notes: const [], edges: const []));
        await paintOnce(c, PsPalette.light);
      } finally {
        c.dispose();
      }
    });
  });
}
