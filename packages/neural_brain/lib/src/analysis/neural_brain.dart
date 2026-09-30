import 'dart:math' as math;

import '../embeddings/text_encoder.dart';
import '../nlp/action_extractor.dart';
import '../nlp/checklist_detector.dart';
import '../nlp/datetime_parser.dart';
import '../nlp/entity_extractor.dart';
import '../nlp/keyword_extractor.dart';
import '../nlp/priority_scorer.dart';
import '../ontology/concept_mapper.dart';
import '../ontology/ontology.dart';
import '../text/language.dart';
import '../text/text_utils.dart';
import '../text/tokenizer.dart';
import 'models.dart';

/// The facade of the on-device "neural brain".
///
/// * [analyzeSync] is the fast path (< 1 ms with the bundled encoder): it is what powers the live
///   hint chips while the user types and the instant classification at save time.
/// * [analyze] additionally computes the retrieval vector when a *remote* encoder is configured.
/// * [profileQuery] prepares a search query for the semantic index.
class NeuralBrain {
  NeuralBrain({
    Ontology? ontology,
    required this.localEncoder,
    TextEncoder? retrievalEncoder,
    this.dates = const DateTimeParser(),
  })  : ontology = ontology ?? Ontology.standard,
        _retrieval = retrievalEncoder {
    mapper = ConceptMapper(this.ontology, encoder: localEncoder, leadVerbs: ActionExtractor.allVerbs);
    actionExtractor = ActionExtractor(dates: dates);
    _entities = EntityExtractor(verbs: ActionExtractor.allVerbs);
    _keywords = KeywordExtractor(extraGeneric: ActionExtractor.allVerbs);
  }

  final Ontology ontology;
  final SyncTextEncoder localEncoder;
  final TextEncoder? _retrieval;
  final DateTimeParser dates;
  late final ConceptMapper mapper;
  late final ActionExtractor actionExtractor;

  static const LanguageDetector _lang = LanguageDetector();
  static const ChecklistDetector _checklists = ChecklistDetector();
  static const PriorityScorer _priority = PriorityScorer();
  late final EntityExtractor _entities;
  late final KeywordExtractor _keywords;

  /// Concepts that describe something happening at a particular time.
  static const Set<String> _eventConcepts = {'appointments', 'meetings', 'events', 'medical', 'lodging', 'transport'};

  /// Identifier of the vector space used for retrieval (persisted with every vector).
  String get retrievalEncoderId => (_retrieval ?? localEncoder).id;
  int get retrievalDim => (_retrieval ?? localEncoder).dim;
  bool get usesRemoteEncoder => _retrieval != null;

  /// Full synchronous analysis (no remote calls). [imageCount] and [context] (e.g. a fetched
  /// link title) let callers fold non-text attachments into classification.
  NoteAnalysis analyzeSync(
    String text, {
    DateTime? now,
    int imageCount = 0,
    String? context,
    bool allowAutoChecklist = true,
  }) {
    final at = now ?? DateTime.now();
    final trimmed = text.trim();
    final language = _lang.detect(trimmed);
    final entities = _entities.extract(trimmed);
    final checklist = allowAutoChecklist ? _checklists.detect(trimmed) : null;
    final confidentChecklist = checklist != null && checklist.isConfident;

    final kind = _kindOf(trimmed, entities, confidentChecklist, imageCount);
    final title = _title(trimmed, kind, checklist, entities);

    // Text fed to the models: no URLs (noise), but keep host words and link context.
    var core = trimmed;
    for (final u in entities.urls.reversed) {
      core = core.replaceRange(u.start, u.end, ' ${u.host.split('.').first} ');
    }
    final itemText = confidentChecklist ? checklist.items.map((i) => i.text).join(', ') : '';
    final embeddingText = collapseWhitespace([
      if (confidentChecklist && checklist.title != null) checklist.title!,
      core,
      if (confidentChecklist && !core.contains(itemText)) itemText,
      ?context,
    ].join('\n'));

    final local = localEncoder.encodeSync(embeddingText);
    final concepts = mapper.activate(embeddingText, language: language, neural: local);

    // Checklist items are not tasks; everything else is scanned for actions.
    var actions = confidentChecklist && checklist.items.length >= 2
        ? const <ExtractedAction>[]
        : actionExtractor.extract(trimmed, now: at, language: language);
    // A verbless event ("Dentist appointment Tuesday 4pm") still deserves a dated entry.
    if (actions.isEmpty && !confidentChecklist && _eventConcepts.any((id) => concepts[id] >= 0.4)) {
      final event = actionExtractor.extractEvent(trimmed, now: at);
      if (event != null) actions = [event];
    }

    final conceptIds = {for (final e in concepts.ranked(min: 0.3)) e.key.id};
    final priority = _priority.assess(trimmed, now: at, actions: actions, conceptIds: conceptIds);

    var domain = concepts.bestDomain();
    final form = mapper.formCue(trimmed);
    if (form != null) {
      // An explicit form ("Idea: ...", "Goal: ...") states the user's intent: it wins over topic.
      final formDomain = ontology.domainsOf(form.id).firstOrNull;
      final dc = formDomain == null ? null : ontology[formDomain];
      if (dc != null) domain = MapEntry(dc, math.max(concepts[dc.id], 0.6));
    }
    // Keywords describe the *topic*: blank out dates first ("12 October", "tomorrow at 5pm").
    var topicText = core;
    for (final e in dates.parse(core, at).reversed) {
      topicText = topicText.replaceRange(e.start, e.end, ' ' * (e.end - e.start));
    }
    final keywords = _keywords.extract(topicText, language: language);
    final suggestion = !confidentChecklist && kind == NoteKind.text && (concepts['groceries'] >= 0.5 || concepts['household_supplies'] >= 0.5)
        ? _checklists.suggestInline(trimmed)
        : checklist != null && !confidentChecklist && kind == NoteKind.text
            ? checklist
            : null;
    final stems = Tokenizer.stems(embeddingText, language: language);
    final words = {for (final t in Tokenizer.content(embeddingText, language: language)) t.norm};
    final tags = _suggestTags(entities, concepts, keywords, language);

    return NoteAnalysis(
      text: trimmed,
      language: language,
      kind: kind,
      title: title,
      checklist: confidentChecklist ? checklist : null,
      checklistSuggestion: suggestion,
      entities: entities,
      actions: actions,
      priority: priority,
      keywords: keywords,
      concepts: concepts,
      categoryId: domain?.key.id,
      categoryConfidence: domain?.value ?? 0,
      tags: tags,
      stems: stems,
      words: words,
      embeddingText: embeddingText,
      localVector: local,
    );
  }

  /// Like [analyzeSync] but also computes the retrieval vector with the remote encoder (if any).
  Future<NoteAnalysis> analyze(
    String text, {
    DateTime? now,
    int imageCount = 0,
    String? context,
    bool allowAutoChecklist = true,
  }) async {
    final a = analyzeSync(text, now: now, imageCount: imageCount, context: context, allowAutoChecklist: allowAutoChecklist);
    final remote = _retrieval;
    if (remote == null) return a;
    final v = await remote.encode(a.embeddingText);
    return NoteAnalysis(
      text: a.text,
      language: a.language,
      kind: a.kind,
      title: a.title,
      checklist: a.checklist,
      checklistSuggestion: a.checklistSuggestion,
      entities: a.entities,
      actions: a.actions,
      priority: a.priority,
      keywords: a.keywords,
      concepts: a.concepts,
      categoryId: a.categoryId,
      categoryConfidence: a.categoryConfidence,
      tags: a.tags,
      stems: a.stems,
      words: a.words,
      embeddingText: a.embeddingText,
      localVector: a.localVector,
      retrievalVector: v,
    );
  }

  /// Understands a search query (concepts, stems, embedding).
  Future<QueryProfile> profileQuery(String query) async {
    final q = query.trim();
    final language = _lang.detect(q);
    final local = localEncoder.encodeSync(q);
    final concepts = mapper.activate(q, language: language, neural: local);
    final vector = _retrieval == null ? local : await _retrieval.encode(q);
    final content = Tokenizer.content(q, language: language);
    return QueryProfile(
      text: q,
      language: language,
      vector: vector,
      concepts: concepts,
      conceptUnit: concepts.unit(),
      stems: Tokenizer.stems(q, language: language),
      words: [for (final t in content) t.norm],
      wordStems: [for (final t in content) Tokenizer.stems(t.raw, language: language)],
      hashtags: _entities.extract(q).hashtags.toSet(),
      onlyHashtags: q.isNotEmpty && q.split(RegExp(r'\s+')).every((w) => w.startsWith('#')),
      confidence: localEncoder.confidence(q),
    );
  }

  // ─────────────────────────────── helpers ───────────────────────────────

  NoteKind _kindOf(String text, Entities e, bool checklist, int imageCount) {
    if (imageCount > 0) return NoteKind.image;
    if (checklist) return NoteKind.checklist;
    if (e.urls.isNotEmpty) {
      var rest = text;
      for (final u in e.urls.reversed) {
        rest = rest.replaceRange(u.start, u.end, '');
      }
      if (Tokenizer.tokenize(rest).length <= 4) return NoteKind.link;
    }
    return NoteKind.text;
  }

  String _title(String text, NoteKind kind, ChecklistDetection? checklist, Entities e) {
    if (text.isEmpty) return kind == NoteKind.image ? 'Photos' : 'Untitled';
    if (kind == NoteKind.checklist && checklist != null) {
      return checklist.title ?? _firstLine(text, e);
    }
    if (kind == NoteKind.link) {
      final u = e.urls.first;
      var rest = text;
      for (final x in e.urls.reversed) {
        rest = rest.replaceRange(x.start, x.end, '');
      }
      rest = collapseWhitespace(rest);
      return rest.isNotEmpty ? rest : u.host;
    }
    return _firstLine(text, e);
  }

  String _firstLine(String text, Entities e) {
    var line = text.split('\n').map((l) => l.trim()).firstWhere((l) => l.isNotEmpty, orElse: () => text);
    line = line.replaceAll(RegExp(r'^(?:#{1,6}\s+|[-*•]\s+|\[[ xX]?\]\s*)'), '');
    for (final u in e.urls.reversed) {
      if (line.contains(u.url)) line = line.replaceFirst(u.url, u.host);
    }
    line = collapseWhitespace(line);
    if (line.length <= 72) return capitalize(line);
    // Prefer ending on a sentence boundary, else cut on a word boundary.
    final sentence = RegExp(r'^(.{24,72}?[.!?])(?:\s|$)').firstMatch(line);
    if (sentence != null) return capitalize(sentence.group(1)!);
    final cut = line.substring(0, 69);
    final space = cut.lastIndexOf(' ');
    return '${capitalize(space > 30 ? cut.substring(0, space) : cut)}…';
  }

  List<TagSuggestion> _suggestTags(
    Entities entities,
    ConceptActivation concepts,
    List<Keyword> keywords,
    Language language,
  ) {
    final tags = <TagSuggestion>[];
    final names = <String>{};
    void add(String name, double conf, TagSource source) {
      final n = name.trim().toLowerCase();
      if (n.length < 2 || !names.add(n)) return;
      tags.add(TagSuggestion(n, conf, source));
    }

    for (final h in entities.hashtags) {
      add(h, 1.0, TagSource.user);
    }
    for (final c in concepts.ranked(min: 0.45, leavesOnly: true).take(2)) {
      add(_conceptTag(c.key, language), c.value, TagSource.concept);
    }
    for (final p in entities.properNouns.take(2)) {
      add(p.replaceAll(' ', '-'), 0.6, TagSource.entity);
    }
    for (final k in keywords.take(2)) {
      final phrase = k.phrase.replaceAll(' ', '-');
      final dup = names.any((n) => n == phrase || n.startsWith(phrase) || phrase.startsWith(n));
      if (!dup && phrase.length >= 3) add(phrase, 0.5, TagSource.keyword);
    }
    tags.sort((a, b) => b.confidence.compareTo(a.confidence));
    return tags.take(6).toList();
  }

  String _conceptTag(Concept c, Language language) {
    if (language == Language.it) {
      final it = foldForMatching(c.labelIt).replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
      if (it.isNotEmpty && it.length <= 18) return it;
    }
    return c.id.replaceAll('_', '-');
  }
}
