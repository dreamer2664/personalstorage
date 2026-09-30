import 'dart:math' as math;
import 'dart:typed_data';

import '../analysis/models.dart';
import '../embeddings/vector_math.dart';
import '../ontology/ontology.dart';

/// Maps a raw cosine similarity onto `[0, 1]`: `clamp((cos - floor) / span)`.
///
/// Different encoders live on different cosine scales (static embeddings rarely exceed 0.5 for
/// related short texts; OpenAI embeddings start around 0.2 for unrelated ones), so the index
/// needs a per-encoder calibration. Values were measured on the bundled sample corpus.
class Calibration {
  const Calibration(this.floor, this.span);

  final double floor;
  final double span;

  double apply(double cos) => ((cos - floor) / span).clamp(0.0, 1.0);

  factory Calibration.forEncoder(String encoderId) {
    if (encoderId.startsWith('potion')) return const Calibration(0.08, 0.50);
    if (encoderId.startsWith('hashing')) return const Calibration(0.05, 0.55);
    if (encoderId.startsWith('cloud')) return const Calibration(0.25, 0.50);
    return const Calibration(0.10, 0.50);
  }
}

/// What the index remembers about a note (kept small; the DB is the source of truth).
class IndexedNote {
  IndexedNote({
    required this.id,
    required this.vector,
    required this.concepts,
    required this.stems,
    required this.createdAt,
    this.words = const {},
    this.keywords = const {},
    this.tags = const {},
    this.categoryId,
  });

  final String id;

  /// Unit-length retrieval embedding.
  final Float32List vector;

  /// Unit-length concept activation vector.
  final Float32List concepts;
  final Set<String> stems;

  /// Folded content words (exact-match tier of the lexical signal).
  final Set<String> words;

  /// Display keywords (lower-case), used for "shares: milk" explanations.
  final Set<String> keywords;
  final Set<String> tags;
  final String? categoryId;
  final DateTime createdAt;

  factory IndexedNote.fromAnalysis(String id, NoteAnalysis a, DateTime createdAt) => IndexedNote(
        id: id,
        vector: a.vector,
        concepts: a.concepts.unit(),
        stems: a.stems,
        words: a.words,
        createdAt: createdAt,
        keywords: {for (final k in a.keywords) k.phrase},
        tags: {for (final t in a.tags) t.name},
        categoryId: a.categoryId,
      );
}

/// A ranked search result with a breakdown for explainability.
class SearchHit {
  const SearchHit({
    required this.id,
    required this.score,
    required this.semantic,
    required this.concept,
    required this.lexical,
    required this.reasons,
  });

  final String id;
  final double score;
  final double semantic;
  final double concept;
  final double lexical;
  final List<String> reasons;

  @override
  String toString() => 'Hit($id ${score.toStringAsFixed(2)} n=${semantic.toStringAsFixed(2)} '
      'c=${concept.toStringAsFixed(2)} l=${lexical.toStringAsFixed(2)})';
}

/// A related note and why it is related.
class Neighbor {
  const Neighbor(this.id, this.score, this.reasons);

  final String id;
  final double score;
  final List<String> reasons;
}

/// In-memory hybrid index: neural vectors + concept vectors + IDF-weighted lexical overlap.
///
/// Brute-force scan by design: for personal libraries (10^3-10^5 notes) a flat scan over
/// 256+K floats is a few milliseconds and beats the complexity of an ANN index. See
/// `docs/AI_ENGINE.md` for the scaling notes.
class SemanticIndex {
  SemanticIndex({required this.ontology, this.calibration = const Calibration(0.08, 0.5)});

  final Ontology ontology;
  Calibration calibration;

  final Map<String, IndexedNote> _notes = {};
  final Map<String, int> _df = {};

  int get length => _notes.length;
  bool contains(String id) => _notes.containsKey(id);
  IndexedNote? operator [](String id) => _notes[id];
  Iterable<IndexedNote> get notes => _notes.values;

  void upsert(IndexedNote note) {
    remove(note.id);
    _notes[note.id] = note;
    for (final s in note.stems) {
      _df[s] = (_df[s] ?? 0) + 1;
    }
  }

  void remove(String id) {
    final old = _notes.remove(id);
    if (old == null) return;
    for (final s in old.stems) {
      final v = (_df[s] ?? 1) - 1;
      if (v <= 0) {
        _df.remove(s);
      } else {
        _df[s] = v;
      }
    }
  }

  void clear() {
    _notes.clear();
    _df.clear();
  }

  double _idf(String stem) => math.log(1 + (_notes.length + 1) / (1 + (_df[stem] ?? 0)));

  // ───────────────────────────── search ─────────────────────────────

  /// Hybrid search. [lexical] optionally carries normalised full-text (BM25) scores keyed by
  /// note id; [restrictTo] limits the candidate set (filters).
  List<SearchHit> search(
    QueryProfile q, {
    int limit = 30,
    double minScore = 0.14,
    Map<String, double> lexical = const {},
    Set<String>? restrictTo,
  }) {
    if (q.isEmpty) return const [];
    final hasConcepts = q.hasConcepts;
    final wN = hasConcepts ? 0.34 : 0.62;
    final wC = hasConcepts ? 0.46 : 0.0;
    final wL = hasConcepts ? 0.20 : 0.38;
    final top = TopK<SearchHit>(limit);

    for (final n in _notes.values) {
      if (restrictTo != null && !restrictTo.contains(n.id)) continue;
      final cosN = n.vector.length == q.vector.length ? dot(q.vector, n.vector) : 0.0;
      final sN = calibration.apply(cosN);
      final sC = hasConcepts ? dot(q.conceptUnit, n.concepts) : 0.0;

      // Two-tier lexical signal: an exact word counts fully, a stem-only match (shops/shopping)
      // counts a little, because stemming conflates unrelated words now and then.
      var overlap = 0.0;
      var allExact = q.words.isNotEmpty;
      for (var i = 0; i < q.words.length; i++) {
        if (n.words.contains(q.words[i])) {
          overlap += 1;
        } else {
          allExact = false;
          if (q.wordStems[i].any(n.stems.contains)) overlap += 0.35;
        }
      }
      overlap = q.words.isEmpty ? 0.0 : overlap / q.words.length;
      final sL = math.max(lexical[n.id] ?? 0.0, overlap);
      final tagMatch = q.hashtags.isNotEmpty && q.hashtags.every(n.tags.contains);
      if (q.onlyHashtags && !tagMatch) continue; // "#q4" is a filter, not a fuzzy query
      // Neural similarity alone (no concept, no shared word) is the weakest evidence: demand a
      // strong match so that gibberish - whose sub-word vectors drift near real notes - finds nothing.
      if (!hasConcepts && sL == 0 && !tagMatch && sN < 0.4 + 0.35 * (1 - q.confidence)) continue;

      var score = wN * sN + wC * sC + wL * sL;
      // A note containing every query word verbatim should outrank purely "semantic" neighbours.
      if (allExact) score = math.max(score, 0.55 + 0.45 * sN);
      if (tagMatch) score = math.max(score, 0.95);
      if (score < minScore || score <= top.threshold) continue;

      top.add(
        score,
        SearchHit(
          id: n.id,
          score: score,
          semantic: sN,
          concept: sC,
          lexical: sL,
          reasons: _explainQuery(q, n, sN, sC, sL),
        ),
      );
    }
    return [for (final e in top.sorted()) e.$2];
  }

  List<String> _explainQuery(QueryProfile q, IndexedNote n, double sN, double sC, double sL) {
    final reasons = <String>[];
    if (sL >= 0.5) reasons.add('Keyword match');
    if (sC >= 0.3) {
      final c = _sharedConcept(q.conceptUnit, n.concepts);
      reasons.add(c != null ? 'Concept: ${c.labelEn}' : 'Related concept');
    }
    if (sN >= 0.3) reasons.add('Similar meaning');
    return reasons;
  }

  Concept? _sharedConcept(Float32List a, Float32List b) {
    var best = -1;
    var bestV = 0.0;
    for (var i = 0; i < a.length; i++) {
      final v = a[i] * b[i];
      if (v > bestV) {
        bestV = v;
        best = i;
      }
    }
    return best < 0 ? null : ontology.concepts[best];
  }

  // ─────────────────────────── relatedness ───────────────────────────

  /// Relatedness of two notes in `[0, 1]`: neural 45% + concept 30% + IDF-weighted lexical 25%,
  /// plus a bonus for shared explicit (user) tags.
  double relatedness(IndexedNote a, IndexedNote b) {
    final sN = a.vector.length == b.vector.length ? calibration.apply(dot(a.vector, b.vector)) : 0.0;
    final sC = dot(a.concepts, b.concepts);
    final sL = _lexicalCosine(a.stems, b.stems);
    var score = 0.45 * sN + 0.30 * sC + 0.25 * sL;
    final sharedTags = a.tags.intersection(b.tags).length;
    if (sharedTags > 0) score += math.min(0.2, 0.1 * sharedTags);
    return score.clamp(0.0, 1.0);
  }

  double _lexicalCosine(Set<String> a, Set<String> b) {
    if (a.isEmpty || b.isEmpty) return 0;
    var inter = 0.0, na = 0.0, nb = 0.0;
    for (final s in a) {
      final w = _idf(s);
      na += w * w;
      if (b.contains(s)) inter += w * w;
    }
    for (final s in b) {
      final w = _idf(s);
      nb += w * w;
    }
    return inter / math.sqrt(na * nb);
  }

  /// The [k] most related notes to [id] scoring at least [minRelatedness].
  List<Neighbor> neighbors(String id, {int k = 5, double minRelatedness = 0.3}) {
    final a = _notes[id];
    if (a == null) return const [];
    final top = TopK<Neighbor>(k);
    for (final b in _notes.values) {
      if (identical(a, b) || a.id == b.id) continue;
      final r = relatedness(a, b);
      if (r < minRelatedness || r <= top.threshold) continue;
      top.add(r, Neighbor(b.id, r, explain(a, b)));
    }
    return [for (final e in top.sorted()) e.$2];
  }

  /// Human readable reasons why [a] and [b] are connected.
  List<String> explain(IndexedNote a, IndexedNote b) {
    final reasons = <String>[];
    final c = _sharedConcept(a.concepts, b.concepts);
    if (c != null && dot(a.concepts, b.concepts) >= 0.25) reasons.add(c.labelEn);
    final kw = a.keywords.intersection(b.keywords);
    if (kw.isNotEmpty) reasons.add('shares: ${kw.take(2).join(', ')}');
    final tags = a.tags.intersection(b.tags);
    if (tags.isNotEmpty && kw.isEmpty) reasons.add('#${tags.first}');
    if (reasons.isEmpty) reasons.add('similar meaning');
    return reasons;
  }
}
