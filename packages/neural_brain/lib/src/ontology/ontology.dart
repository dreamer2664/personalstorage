import 'dart:math' as math;

import '../text/language.dart';
import '../text/stopwords.dart';
import '../text/text_utils.dart';
import 'default_ontology.dart';

/// A single lexical trigger of a [Concept].
class OntologyTerm {
  const OntologyTerm(this.phrase, this.weight, {this.anchored = false});

  /// Space separated words, not yet stemmed.
  final String phrase;

  /// 1.6 for strong (`!`) terms, 1.3 for single-word labels, 1.0 default, 0.4 for weak (`~`).
  final double weight;

  /// `^term`: only counts at the start of a line or sentence ("Idea: ...", "Goal: ...").
  final bool anchored;

  int get wordCount => phrase.split(' ').length;
}

/// A node in the concept hierarchy (a DAG: a concept may have several parents).
class Concept {
  Concept({
    required this.id,
    required this.index,
    required this.parents,
    required this.labelEn,
    required this.labelIt,
    required this.termsEn,
    required this.termsIt,
    this.prior = 1.0,
  });

  final String id;

  /// Tie-breaking weight used *only* when choosing a note's category (`learning@0.85`):
  /// "activity" domains such as learning/ideas yield to topical ones when both fire.
  final double prior;

  /// Position in dense concept vectors.
  final int index;
  final List<String> parents;
  final String labelEn;
  final String labelIt;
  final List<OntologyTerm> termsEn;
  final List<OntologyTerm> termsIt;

  /// Top-level concepts double as user-visible categories.
  bool get isDomain => parents.isEmpty;

  String label(Language language) => language == Language.it ? labelIt : labelEn;

  @override
  String toString() => 'Concept($id)';
}

/// A bilingual concept hierarchy parsed from the compact DSL described in
/// `default_ontology.dart`.
class Ontology {
  Ontology._(this.concepts, this.version) : _byId = {for (final c in concepts) c.id: c};

  final List<Concept> concepts;
  final int version;
  final Map<String, Concept> _byId;

  /// The ontology shipped with the app.
  static final Ontology standard = Ontology.parse(defaultOntologyDsl, version: defaultOntologyVersion);

  Concept? operator [](String id) => _byId[id];

  int get size => concepts.length;

  Iterable<Concept> get domains => concepts.where((c) => c.isDomain);

  Iterable<Concept> childrenOf(String id) => concepts.where((c) => c.parents.contains(id));

  /// All ancestors of [id] (transitive, excluding itself).
  Set<String> ancestors(String id) {
    final out = <String>{};
    void walk(String cur) {
      for (final p in _byId[cur]?.parents ?? const <String>[]) {
        if (out.add(p)) walk(p);
      }
    }

    walk(id);
    return out;
  }

  /// The top-level domain(s) a concept rolls up to.
  Set<String> domainsOf(String id) {
    final c = _byId[id];
    if (c == null) return const {};
    if (c.isDomain) return {id};
    return ancestors(id).where((a) => _byId[a]?.isDomain ?? false).toSet();
  }

  /// Parses the DSL. Throws [FormatException] on malformed lines or dangling parents.
  factory Ontology.parse(String dsl, {int version = 1}) {
    final concepts = <Concept>[];
    final ids = <String>{};
    for (final rawLine in dsl.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final parts = line.split('|').map((s) => s.trim()).toList();
      if (parts.length != 4) throw FormatException('Ontology line needs 4 fields: $line');
      final head = parts[0].split('>').map((s) => s.trim()).toList();
      if (head.length != 2) throw FormatException('Missing ">" in: $line');
      final idParts = head[0].split('@');
      final id = idParts[0].trim();
      final prior = idParts.length > 1 ? double.parse(idParts[1]) : 1.0;
      if (!ids.add(id)) throw FormatException('Duplicate concept id: $id');
      final parents = head[1] == '-' ? <String>[] : head[1].split(',').map((s) => s.trim()).toList();

      final termSplit = parts[3].split(';');
      final en = _terms(termSplit[0]);
      final it = termSplit.length > 1 ? _terms(termSplit[1]) : List<OntologyTerm>.of(en);
      _addLabelTerm(en, parts[1]);
      _addLabelTerm(it, parts[2]);
      concepts.add(
        Concept(
          id: id,
          index: concepts.length,
          parents: parents,
          labelEn: parts[1],
          labelIt: parts[2],
          termsEn: en,
          termsIt: it,
          prior: prior,
        ),
      );
    }
    for (final c in concepts) {
      for (final p in c.parents) {
        if (!ids.contains(p)) throw FormatException('Concept ${c.id} has unknown parent "$p"');
      }
    }
    return Ontology._(concepts, version);
  }

  static int _commonPrefix(String a, String b) {
    var i = 0;
    while (i < a.length && i < b.length && a[i] == b[i]) {
      i++;
    }
    return i;
  }

  /// Parses whitespace separated terms. Markers (any order, prefix): `~` weak, `!` strong,
  /// `^` anchored to the start of a line/sentence.
  static List<OntologyTerm> _terms(String raw) {
    final out = <OntologyTerm>[];
    for (var tok in raw.trim().split(RegExp(r'\s+'))) {
      if (tok.isEmpty) continue;
      var weight = 1.0;
      var anchored = false;
      while (tok.isNotEmpty && '~!^'.contains(tok[0])) {
        if (tok[0] == '~') weight = 0.4;
        if (tok[0] == '!') weight = 1.6;
        if (tok[0] == '^') anchored = true;
        tok = tok.substring(1);
      }
      final phrase = foldForMatching(tok.replaceAll('_', ' '));
      if (phrase.isEmpty) continue;
      out.add(OntologyTerm(phrase, weight, anchored: anchored));
    }
    return out;
  }

  /// A *single-word* label ("Groceries") is also a search term, so people can find the concept by
  /// typing its name. Multi-word labels ("Flights & transport") are not auto-expanded - their
  /// words are generic ("ideas", "product") and must be listed explicitly. An explicit term
  /// with the same spelling always wins (so `~book` stays weak in the "Books" concept).
  static void _addLabelTerm(List<OntologyTerm> terms, String label) {
    final words = foldForMatching(
      label,
    ).split(RegExp(r'[^\p{L}\d]+', unicode: true)).where((w) => w.isNotEmpty && !allStopwords.contains(w)).toList();
    if (words.length != 1 || words.first.length < 3) return;
    final w = words.first;
    // Skip if an explicit term already covers this word or an inflected form of it
    // (book/books, appuntamento/appuntamenti): near-identical spelling counts as the same word.
    if (terms.any(
      (t) =>
          !t.anchored &&
          !t.phrase.contains(' ') &&
          _commonPrefix(t.phrase, w) >= math.max(4, math.min(t.phrase.length, w.length) - 2),
    )) {
      return;
    }
    terms.add(OntologyTerm(w, 1.3));
  }
}
