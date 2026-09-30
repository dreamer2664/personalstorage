import 'dart:math' as math;
import 'dart:typed_data';

import '../embeddings/text_encoder.dart';
import '../embeddings/vector_math.dart';
import '../text/language.dart';
import '../text/stemmer.dart';
import '../text/stopwords.dart';
import '../text/tokenizer.dart';
import 'ontology.dart';

/// Result of mapping a text onto the concept hierarchy.
class ConceptActivation {
  ConceptActivation(this.ontology, this.values);

  final Ontology ontology;

  /// Activation in `[0, 1]` per concept (index == [Concept.index]), hierarchy propagated.
  final Float32List values;

  static const double noise = 0.08;

  bool get isEmpty => values.every((v) => v < noise);

  double operator [](String id) {
    final c = ontology[id];
    return c == null ? 0 : values[c.index];
  }

  /// Concepts ranked by activation, strongest first.
  List<MapEntry<Concept, double>> ranked({
    double min = 0.25,
    bool domainsOnly = false,
    bool leavesOnly = false,
  }) {
    final out = <MapEntry<Concept, double>>[];
    for (final c in ontology.concepts) {
      final v = values[c.index];
      if (v < min) continue;
      if (domainsOnly && !c.isDomain) continue;
      if (leavesOnly && c.isDomain) continue;
      out.add(MapEntry(c, v));
    }
    out.sort((a, b) => b.value.compareTo(a.value));
    return out;
  }

  /// The domain (category) a note most likely belongs to, honouring each domain's `prior`.
  /// Returns the raw activation as value, or null when nothing reaches [min].
  MapEntry<Concept, double>? bestDomain({double min = 0.3}) {
    MapEntry<Concept, double>? best;
    var bestScore = 0.0;
    for (final c in ontology.domains) {
      final v = values[c.index];
      if (v < min) continue;
      final s = v * c.prior;
      if (s > bestScore) {
        bestScore = s;
        best = MapEntry(c, v);
      }
    }
    return best;
  }

  /// Sparse representation used for persistence (`{"groceries": 0.83, ...}`).
  Map<String, double> toSparse() => {
    for (final c in ontology.concepts)
      if (values[c.index] >= noise) c.id: double.parse(values[c.index].toStringAsFixed(3)),
  };

  static ConceptActivation fromSparse(Ontology ontology, Map<String, Object?> sparse) {
    final v = Float32List(ontology.size);
    sparse.forEach((id, value) {
      final c = ontology[id];
      if (c != null && value is num) v[c.index] = value.toDouble();
    });
    return ConceptActivation(ontology, v);
  }

  /// L2 normalised copy, suitable for cosine similarity.
  Float32List unit() {
    final out = Float32List(values.length);
    for (var i = 0; i < values.length; i++) {
      out[i] = values[i] < noise ? 0 : values[i];
    }
    normalizeInPlace(out);
    return out;
  }
}

class _Posting {
  const _Posting(this.concept, this.weight, {this.strong = false});
  final int concept;
  final double weight;

  /// Marked `!` in the ontology: never damped, even when it starts a clause.
  final bool strong;
}

class _Index {
  final Map<String, List<_Posting>> free = {};
  final Map<String, List<_Posting>> anchored = {};
}

/// Maps free text to [ConceptActivation]s by combining
///  1. **lexical evidence** - stemmed unigram/phrase lookups against the ontology (per language),
///  2. **form cues** - structural patterns such as `Idea: ...`, `Goal: ...`, `"quote" - Author`,
///  3. **neural evidence** - cosine between the note embedding and each concept centroid, and
///  4. **hierarchy propagation** - children lift their parents (noisy-OR, so breadth counts).
class ConceptMapper {
  ConceptMapper(
    this.ontology, {
    SyncTextEncoder? encoder,
    this.leadVerbs = const {},
  }) {
    _en = _buildIndex((c) => c.termsEn, Stemmer.english);
    _it = _buildIndex((c) => c.termsIt, Stemmer.italian);
    if (encoder != null) _buildCentroids(encoder);
    _order = [...ontology.concepts]..sort((a, b) => _depth(b).compareTo(_depth(a)));
  }

  final Ontology ontology;

  /// Folded action verbs ("buy", "book", "comprare"). A verb that *starts* a clause describes the
  /// action, not the topic ("Book flights": travel, not books), so its lexical weight is damped.
  final Set<String> leadVerbs;

  late final _Index _en;
  late final _Index _it;
  late final List<Concept> _order;
  static const int _maxPhrase = 3;
  static const double _leadVerbDamping = 0.3;
  static const double _domainTermFactor = 0.8;

  /// Concept centroids in neural space (null when no encoder was supplied).
  List<Float32List>? _centroids;
  int _neuralDim = 0;

  /// How much a child's activation lifts its *primary* (first-listed) parent...
  static const double parentDecay = 0.8;

  /// ...and any additional parent ("groceries" is mostly shopping, somewhat food).
  static const double secondaryParentDecay = 0.45;

  static final List<(RegExp, String, double)> _formCues = [
    (
      RegExp(r'^\s*(?:idea|ideas|startup idea|app idea|brainstorm|what if|idea per|idee)\b', caseSensitive: false),
      'ideas',
      1.6,
    ),
    (
      RegExp(r'^\s*["“«‘].{4,}["”»’]\s*(?:[-–—~]\s*\p{Lu}[\p{L}. ]{1,40})?\s*$', unicode: true, dotAll: true),
      'quotes',
      1.8,
    ),
    (RegExp(r'^\s*(?:dear diary|caro diario|today i |oggi ho |oggi mi sono )', caseSensitive: false), 'journal', 1.6),
    (
      RegExp(r'^\s*(?:goal|goals|obiettivo|obiettivi|resolution|new year)\b.{0,20}:', caseSensitive: false),
      'goals_habits',
      1.6,
    ),
    (RegExp(r'^\s*(?:meeting notes|minutes|agenda|riunione|verbale)\s*[:\-–]', caseSensitive: false), 'meetings', 1.6),
    (RegExp(r'^\s*(?:watch ?list|to watch|da guardare)\s*[:\-–]', caseSensitive: false), 'movies_tv', 1.6),
    (RegExp(r'^\s*(?:reading list|to read|da leggere)\s*[:\-–]', caseSensitive: false), 'books', 1.6),
    (RegExp(r'^\s*(?:recipe|ricetta)\b.{0,30}:', caseSensitive: false), 'recipes', 1.6),
  ];

  _Index _buildIndex(List<OntologyTerm> Function(Concept) termsOf, String Function(String) stem) {
    final free = <String, Map<int, (double, bool)>>{};
    final anchored = <String, Map<int, (double, bool)>>{};
    for (final c in ontology.concepts) {
      for (final t in termsOf(c)) {
        final key = t.phrase.split(' ').map(stem).join(' ');
        final bucket = (t.anchored ? anchored : free).putIfAbsent(key, () => {});
        // Domain-level words ("payment", "work") are broader than leaf-level ones ("unit test").
        final w = t.weight * (c.isDomain ? _domainTermFactor : 1.0);
        final prev = bucket[c.index];
        if (prev == null || w > prev.$1) bucket[c.index] = (w, t.weight >= 1.5);
      }
    }
    // Specificity: a term shared by many concepts is less informative.
    const spec = [1.0, 1.0, 0.8, 0.65, 0.5];
    Map<String, List<_Posting>> finish(Map<String, Map<int, (double, bool)>> raw) => {
      for (final e in raw.entries)
        e.key: [
          for (final p in e.value.entries)
            _Posting(p.key, p.value.$1 * spec[math.min(e.value.length, 4)], strong: p.value.$2),
        ],
    };
    return _Index()
      ..free.addAll(finish(free))
      ..anchored.addAll(finish(anchored));
  }

  void _buildCentroids(SyncTextEncoder encoder) {
    _neuralDim = encoder.dim;
    _centroids = [
      for (final c in ontology.concepts)
        encoder.encodeSync(
          '${c.labelEn}: ${c.termsEn.where((t) => !t.anchored && t.weight >= 1).take(18).map((t) => t.phrase).join(', ')}',
        ),
    ];
  }

  /// Maps [text] (optionally with its precomputed [neural] embedding) to concepts.
  ConceptActivation activate(
    String text, {
    Language language = Language.unknown,
    Float32List? neural,
  }) {
    final n = ontology.size;
    final evidence = Float64List(n);
    final tokens = Tokenizer.tokenize(text);
    final norms = [for (final t in tokens) t.norm];
    final useEn = language != Language.it;
    final useIt = language != Language.en;
    final enStems = [for (final w in norms) Stemmer.english(w)];
    final itStems = [for (final w in norms) Stemmer.italian(w)];
    final seen = <String, int>{};

    // Clause starts: first token, or after a newline / sentence end.
    final clauseStart = List<bool>.filled(norms.length, false);
    for (var i = 0; i < tokens.length; i++) {
      clauseStart[i] = i == 0 || RegExp(r'[\n.!?;:]').hasMatch(text.substring(tokens[i - 1].end, tokens[i].start));
    }
    final dampLeadVerbs = norms.length >= 3;

    void accumulate(List<_Posting> postings, String key, double scale, {bool dampWeak = false}) {
      for (final p in postings) {
        final slot = '${p.concept}:$key';
        final k = (seen[slot] ?? 0) + 1;
        seen[slot] = k;
        final damp = dampWeak && !p.strong ? _leadVerbDamping : 1.0;
        evidence[p.concept] += p.weight * scale * damp * math.pow(0.6, k - 1);
      }
    }

    var i = 0;
    while (i < norms.length) {
      var consumed = 0;
      for (var len = math.min(_maxPhrase, norms.length - i); len >= 1 && consumed == 0; len--) {
        final isStopUnigram = len == 1 && (allStopwords.contains(norms[i]) || norms[i].length < 2);
        final boost = 1 + 0.35 * (len - 1);
        final isLeadVerb = len == 1 && dampLeadVerbs && clauseStart[i] && leadVerbs.contains(norms[i]);
        var matched = false;

        void lookup(_Index idx, List<String> stems) {
          final key = stems.sublist(i, i + len).join(' ');
          final free = isStopUnigram ? null : idx.free[key];
          if (free != null) {
            // A clause-initial verb describes the action, not the topic - unless the ontology
            // marked the term as strong (`!renew`).
            accumulate(free, key, boost, dampWeak: isLeadVerb);
            matched = true;
          }
          if (clauseStart[i]) {
            final anchored = idx.anchored[key];
            if (anchored != null) {
              accumulate(anchored, '^$key', boost);
              matched = true;
            }
          }
        }

        if (useEn) lookup(_en, enStems);
        if (useIt && !(useEn && _sameStems(enStems, itStems, i, len))) lookup(_it, itStems);
        if (matched) consumed = len;
      }
      i += consumed == 0 ? 1 : consumed;
    }

    for (final cue in _formCues) {
      if (cue.$1.hasMatch(text)) {
        final c = ontology[cue.$2];
        if (c != null) evidence[c.index] += cue.$3;
      }
    }

    final act = Float32List(n);
    final cents = _centroids;
    for (var c = 0; c < n; c++) {
      var a = evidence[c] <= 0 ? 0.0 : 1 - math.exp(-0.9 * evidence[c]);
      if (cents != null && neural != null && neural.length == _neuralDim) {
        final cos = dot(neural, cents[c]) / (norm(cents[c]) + 1e-9);
        final nv = ((cos - 0.22) / 0.33).clamp(0.0, 1.0) * 0.55;
        a = 1 - (1 - a) * (1 - nv);
      }
      act[c] = a.toDouble();
    }
    // Propagate children -> parents with noisy-OR (deepest concepts first), so a domain backed by
    // several independent children outranks one backed by a single lucky word.
    for (final c in _order) {
      final a = act[c.index];
      if (a <= 0) continue;
      for (var k = 0; k < c.parents.length; k++) {
        final pi = ontology[c.parents[k]]!.index;
        act[pi] = 1 - (1 - act[pi]) * (1 - (k == 0 ? parentDecay : secondaryParentDecay) * a);
      }
    }
    return ConceptActivation(ontology, act);
  }

  /// If [text] follows an explicit *form* ("Idea: ...", "Goal: ...", `"quote" - Author`, "Watch
  /// list: ..."), returns the concept that form names - a strong statement of user intent that
  /// overrides topical evidence when choosing a category.
  Concept? formCue(String text) {
    for (final cue in _formCues) {
      if (cue.$1.hasMatch(text)) return ontology[cue.$2];
    }
    return null;
  }

  static bool _sameStems(List<String> a, List<String> b, int i, int len) {
    for (var k = i; k < i + len; k++) {
      if (a[k] != b[k]) return false;
    }
    return true;
  }

  final Map<String, int> _depthCache = {};
  int _depth(Concept c) => _depthCache.putIfAbsent(c.id, () {
    if (c.parents.isEmpty) return 0;
    return 1 + c.parents.map((p) => _depth(ontology[p]!)).reduce(math.max);
  });
}
