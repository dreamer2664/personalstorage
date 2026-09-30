import 'package:neural_brain/neural_brain.dart';

import '../data/repositories/note_repository.dart';
import '../domain/models.dart';
import 'brain_service.dart';

class SearchResult {
  const SearchResult(this.note, this.score, this.reasons);

  final NoteSummary note;
  final double score;

  /// Why it matched ("Concept: Groceries", "Similar meaning", "Keyword match").
  final List<String> reasons;
}

/// Hybrid search: SQLite FTS5 (BM25, prefix) fused with the neural + concept index.
///
/// The FTS ranks exact/prefix word matches; the index adds *meaning* ("groceries" -> "milk and
/// eggs"). Scores are combined inside [SemanticIndex.search]; FTS-only hits (notes the index
/// doesn't know yet) are still returned, so results are never missing while enrichment catches up.
class SearchService {
  SearchService({required this.repo, required this.brain});

  final NoteRepository repo;
  final BrainService brain;

  Future<List<SearchResult>> search(String query, {int limit = 40}) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final lexical = await repo.lexicalScores(q);
    final profile = await brain.brain.profileQuery(q);
    final hits = brain.index.search(profile, limit: limit, lexical: lexical);

    final byId = <String, SearchHit>{for (final h in hits) h.id: h};
    // Notes found by FTS but not (yet) in the index.
    for (final e in lexical.entries) {
      if (!byId.containsKey(e.key) && e.value >= 0.3 && !brain.index.contains(e.key)) {
        byId[e.key] = SearchHit(
          id: e.key,
          score: 0.4 + 0.3 * e.value,
          semantic: 0,
          concept: 0,
          lexical: e.value,
          reasons: const ['Keyword match'],
        );
      }
    }
    if (byId.isEmpty) return const [];
    final summaries = {for (final s in await repo.loadSummaries(ids: byId.keys.toSet(), limit: limit * 2)) s.id: s};
    final out = [
      for (final h in byId.values)
        if (summaries[h.id] != null) SearchResult(summaries[h.id]!, h.score, h.reasons),
    ]..sort((a, b) => b.score.compareTo(a.score));
    return out.take(limit).toList();
  }

  /// Notes related to [noteId], with the reason for each connection.
  Future<List<SearchResult>> related(String noteId, {int limit = 6, double minRelatedness = 0.28}) async {
    final neighbors = brain.index.neighbors(noteId, k: limit, minRelatedness: minRelatedness);
    if (neighbors.isEmpty) return const [];
    final summaries = {
      for (final s in await repo.loadSummaries(ids: {for (final n in neighbors) n.id})) s.id: s,
    };
    return [
      for (final n in neighbors)
        if (summaries[n.id] != null) SearchResult(summaries[n.id]!, n.score, n.reasons),
    ];
  }
}
