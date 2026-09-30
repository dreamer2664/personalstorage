import 'package:neural_brain/neural_brain.dart';

import '../data/repositories/note_repository.dart';

/// Builds the [KnowledgeGraph] shown in the Graph tab from stored notes and edges.
class GraphService {
  GraphService(this.repo, {this.ontology});

  final NoteRepository repo;

  /// Lets clusters be named after ontology concepts ("Clients & sales") instead of raw tag slugs.
  final Ontology? ontology;

  /// [minWeight] is the "connection strength" slider; [tagHubs] adds tag nodes.
  Future<KnowledgeGraph> load({
    double minWeight = 0.33,
    bool tagHubs = false,
    String Function(String)? categoryLabel,
  }) async {
    final notes = await repo.graphNotes();
    final edges = await repo.db.select(repo.db.edges).get();
    return GraphBuilder.build(
      notes: [
        for (final n in notes)
          GraphNoteInput(
            id: n.id,
            label: n.title,
            categoryId: n.categoryId,
            importance: 1 + 0.35 * n.priority + (n.pinned ? 0.6 : 0),
            tags: n.tags,
          ),
      ],
      edges: [
        for (final e in edges)
          GraphEdgeInput(
            e.a,
            e.b,
            e.weight,
            kind: e.kind == 'link' ? GraphEdgeKind.link : GraphEdgeKind.semantic,
            reason: e.reason,
          ),
      ],
      minWeight: minWeight,
      includeTagNodes: tagHubs,
      categoryLabel: categoryLabel,
      tagLabel: (tag) => ontology?[tag.replaceAll('-', '_')]?.labelEn,
    );
  }
}
