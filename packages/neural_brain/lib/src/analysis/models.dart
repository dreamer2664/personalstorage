import 'dart:typed_data';

import '../nlp/action_extractor.dart';
import '../nlp/checklist_detector.dart';
import '../nlp/entity_extractor.dart';
import '../nlp/keyword_extractor.dart';
import '../nlp/priority_scorer.dart';
import '../ontology/concept_mapper.dart';
import '../text/language.dart';

/// Structural type of a note.
enum NoteKind {
  text,
  checklist,
  link,
  image;

  static NoteKind parse(String? raw) => NoteKind.values.firstWhere((k) => k.name == raw, orElse: () => NoteKind.text);
}

/// Where a tag came from (user tags always win over AI tags in the UI).
enum TagSource { user, concept, entity, keyword }

class TagSuggestion {
  const TagSuggestion(this.name, this.confidence, this.source);

  final String name;
  final double confidence;
  final TagSource source;

  @override
  String toString() => '#$name(${confidence.toStringAsFixed(2)} ${source.name})';
}

/// Everything the brain infers from one note. Immutable; safe to pass across isolates except for
/// the typed-data fields, which are copied.
class NoteAnalysis {
  const NoteAnalysis({
    required this.text,
    required this.language,
    required this.kind,
    required this.title,
    required this.entities,
    required this.actions,
    required this.priority,
    required this.keywords,
    required this.concepts,
    required this.categoryId,
    required this.categoryConfidence,
    required this.tags,
    required this.stems,
    required this.words,
    required this.embeddingText,
    required this.localVector,
    this.checklist,
    this.checklistSuggestion,
    this.retrievalVector,
  });

  final String text;
  final Language language;
  final NoteKind kind;
  final String title;
  final ChecklistDetection? checklist;

  /// A *suggested* (not applied) conversion, e.g. "milk and eggs" -> two checklist items.
  final ChecklistDetection? checklistSuggestion;
  final Entities entities;
  final List<ExtractedAction> actions;
  final PriorityAssessment priority;
  final List<Keyword> keywords;
  final ConceptActivation concepts;

  /// Top-level ontology domain (e.g. `finance`), or null when nothing matched confidently.
  final String? categoryId;
  final double categoryConfidence;
  final List<TagSuggestion> tags;

  /// Distinct content stems, used for lexical overlap and IDF weighting.
  final Set<String> stems;

  /// Distinct folded content words (exact-match tier of lexical search).
  final Set<String> words;

  /// The text that was embedded (title + body + list items + link context).
  final String embeddingText;

  /// Vector from the always-available local encoder (used for concept evidence).
  final Float32List localVector;

  /// Vector used for retrieval; equals [localVector] unless a cloud encoder is configured.
  final Float32List? retrievalVector;

  Float32List get vector => retrievalVector ?? localVector;

  bool get hasTasks => actions.isNotEmpty;
}

/// A search query understood by the brain.
class QueryProfile {
  const QueryProfile({
    required this.text,
    required this.language,
    required this.vector,
    required this.concepts,
    required this.conceptUnit,
    required this.stems,
    required this.words,
    required this.wordStems,
    required this.hashtags,
    this.onlyHashtags = false,
    this.confidence = 1.0,
  });

  final String text;
  final Language language;

  /// Retrieval-space embedding.
  final Float32List vector;
  final ConceptActivation concepts;
  final Float32List conceptUnit;
  final Set<String> stems;

  /// Folded content words of the query and, in parallel, the stems of each word.
  final List<String> words;
  final List<Set<String>> wordStems;
  final Set<String> hashtags;

  /// The query consists solely of `#tags` (a tag filter).
  final bool onlyHashtags;

  /// How reliable the neural similarity is for this query (see [SyncTextEncoder.confidence]).
  final double confidence;

  bool get hasConcepts => !concepts.isEmpty;
  bool get isEmpty => text.trim().isEmpty;
}
