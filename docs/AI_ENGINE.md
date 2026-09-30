# The "Neural Brain"

Everything in this document runs **on the device, offline**, in the pure-Dart package
[`packages/neural_brain`](../packages/neural_brain). It turns raw text into structure:

```
text ─► language ─► entities ─► dates ─► actions ─► checklist ─► concepts ─► category · tags · priority
                                              │                        │
                                              └───── neural vector ────┴─► hybrid search · related notes · graph edges
```

Design principle: **symbolic and neural evidence, combined.** A static embedding model alone is not
enough for short notes (measured below), and a hand-written lexicon alone cannot generalise; together they
are fast, explainable and surprisingly robust.

## 1. Neural layer - static embeddings

* Model: **potion-base-8M** (Model2Vec, distilled from `bge-base-en-v1.5`), 256-d, 29,528-token WordPiece
  vocabulary, MIT. A sentence vector is the *mean of token vectors* - no transformer at runtime, so there
  is no native runtime, no GPU and no latency spike (27-37 µs per sentence).
* Shipped as a single 7.9 MB `PSM1` file: the float32 matrix is **row-wise int8 quantised** (29 MB -> 7.9 MB,
  cosine to the float32 vectors >= 0.99994 on the fixtures). `tool/build_static_model.py` produces it from the
  Hugging Face checkpoint and also emits reference fixtures.
* The tokenizer is a from-scratch Dart port of BERT's normaliser + pre-tokenizer + WordPiece
  (accent stripping, CJK padding, punctuation splitting, `##` continuation, UNK handling). A test checks
  **exact token-id parity with the Python reference on 27 adversarial strings** (accents, CJK, emoji, URLs,
  100+ character words, empty input) and embedding parity within int8 error.
* `SyncTextEncoder.confidence(text)` reports how much the model "understands" a string (words that shatter
  into sub-word fragments score ~0). The index refuses neural-only matches for low-confidence queries,
  which is why gibberish returns nothing instead of a random note.

**Why not a bigger model?** Measured on the sample corpus, the neural layer alone ranks "Call mom about
Sunday lunch" above "milk and eggs" for the query "groceries". Short queries are where static models are
weakest. A bigger neural model would cost megabytes and milliseconds and still miss; the ontology fixes it
cheaply and explainably.

## 2. Symbolic layer - bilingual concept ontology

A DSL (`default_ontology.dart`, 67 concepts, 14 domains, ~1,180 English and ~820 Italian terms):

```
groceries > shopping,food | Groceries | Spesa | milk egg bread olive_oil ... ; latte uova pane ...
```

* `>` lists parents (first = primary). Domains (no parent) are the user-visible **categories**.
* Markers: `~weak` (ambiguous words like `call`, `book`), `!strong`, `^anchored` (only at the start of a
  line/sentence: `^idea` matches "Idea: ..." but not "gift ideas"), `id@0.85` domain prior.
* Terms are stemmed (light English + Italian stemmers), so `egg` matches `eggs`, `uovo` matches `uova`.

### Concept activation (`ConceptMapper`)

For each concept `c`:

1. **Lexical**: sum of matched term weights (phrases up to 3 words, repeats decay by 0.6, terms shared by many
   concepts are down-weighted, domain-level words count 0.8x a leaf-level word, a clause-initial verb counts
   0.3x unless strong), squashed with `1 - exp(-0.9 * evidence)`.
2. **Form cues**: `Idea:`, `Goal:`, `Watch list:`, `"quote" - Author`, `Meeting notes:` ... add strong evidence
   for the concept they name and decide the category outright (explicit user intent beats topic).
3. **Neural**: cosine between the note vector and the concept's *centroid* (embedding of its label + exemplar
   terms), rescaled: `clamp((cos - 0.22)/0.33) * 0.55`, combined by noisy-OR.
4. **Hierarchy**: children lift parents with noisy-OR (primary parent x0.8, others x0.45), so *breadth of
   evidence* counts: `milk` -> `groceries` -> `shopping`.

The result is a 67-d vector per note. It drives the category (argmax over domains with priors), the tags
(top leaf concepts + entities + keywords), and the concept half of search and graph similarity.

### Accuracy (measured, and how to read it)

| Set | Notes | Result | Caveat |
|---|---|---|---|
| Sample corpus (EN + IT) | 33 labelled | 33/33 | **tuned on** - an upper bound |
| Held-out v1 | 30 | 24/30 (80%) on first evaluation, 28/30 after one round of *general* fixes | partly tuned-on afterwards |
| Fresh v2 | 28 | **23/28 (82%)** on its one untouched evaluation; 27/28 after adding the vocabulary the misses revealed | tuned-on afterwards |

The honest estimate for unseen notes is **~80-85% correct category**; most misses are "no category"
(the note stays in *General*) rather than a wrong one. Regressions are guarded by tests
(`brain_quality_test.dart`, thresholds at 90% on the tuned sets). Extending the ontology is the main lever.

## 3. Rule-based NLP

| Component | Highlights |
|---|---|
| **Date/time parser** (EN + IT) | today/tomorrow/dopodomani, weekdays with this/next/"prossimo", `in 2 hours`, `tra 3 giorni`, `12/10`, `12 Oct`, `October 12th`, `2026-10-12`, clock times (`5pm`, `17:30`, `at 5`, `alle 17`), day parts (`tonight`, `domani mattina`), end of week/month, weekends, **deadline markers** (`by`, `entro`, `prima di`). Bare hours use a documented am/pm heuristic. *Attributive* uses ("Sunday lunch", "Monday client presentation") are flagged so they never become a due date. |
| **Action extractor** | explicit cues (`remind me to`, `don't forget`, `I need to`, `todo:`, `ricordami di`, `devo`), *strong* imperative verbs (`buy`, `call`, `pay`...), *soft* verbs only with a date or cue, multi-action splitting ("Buy milk and call mom tomorrow" -> two tasks sharing the date), questions and past tense ignored, verbless events ("Dentist appointment Tuesday 4pm") become dated items. |
| **Checklist detector** | markdown/bullets/checkboxes, cue + inline list (`shopping list: a, b and c`), buy phrases with >= 3 items, short lines; low-confidence cases ("milk and eggs") are *suggested*, never forced. |
| **Priority** | transparent additive score with human-readable reasons: urgent/important wording, deadline, due-date proximity, bills/medical boosts, "someday/maybe" penalty. |
| **Entities / keywords** | URLs, e-mails, phones, `#tags`, `@mentions`, `[[wikilinks]]`, money, proper nouns (quote-aware); RAKE-style keyphrases that ignore verbs and calendar words. |

## 4. Hybrid semantic search

`SemanticIndex.search` scores every note with three signals and fuses them:

```
concept query:     score = 0.34·neural + 0.46·concept + 0.20·lexical
no concepts:       score = 0.62·neural + 0.38·lexical        (neural alone needs a high bar)
all words present verbatim:  score ≥ 0.55 + 0.45·neural
#tag query:        exact tag filter
```

* *neural* = calibrated cosine (`Calibration` per encoder: potion maps cos 0.08-0.58 onto 0-1).
* *concept* = cosine of concept vectors (hierarchy-aware, language-independent: the Italian query
  "spesa" finds the English "milk and eggs").
* *lexical* = exact word matches count fully, stem-only matches count 0.35 (stemming conflates `shops` and
  `shopping`), blended with SQLite **FTS5 BM25** (prefix and accent-insensitive).
* Every hit carries **reasons** shown in the UI ("Keyword match · Concept: Groceries · Similar meaning").

Headline example, from the test-suite: *"groceries"* returns *Milk and eggs*, *Buy bread, pasta and tomatoes*,
*Shopping list* and the Italian *Comprare latte, uova e pane* - and nothing about login bugs.

## 5. Related notes and graph edges

`relatedness(a, b) = 0.45·neural + 0.30·concept + 0.25·IDF-weighted lexical cosine (+ shared user tags)`.
After every capture the queue stores the top-6 neighbours above 0.26; the Graph tab filters by a user
slider (default 0.33). See [GRAPH.md](GRAPH.md).

## 6. Optional cloud embeddings

`CloudTextEncoder` speaks the OpenAI-compatible `/embeddings` API (OpenAI, Azure, Ollama, LM Studio,
vLLM). It is **off by default**, replaces only the *retrieval* vector space (categorisation, tasks and
concepts stay local) and triggers an automatic background re-embedding because the stored `model_id`
changes. The API key lives in secure storage.

## Limitations

* English-centric embeddings; Italian relies on the ontology and lexical layers.
* The ontology is hand-written: unusual domains fall back to *General* until vocabulary is added.
* The date parser covers common personal-note phrasings, not every natural-language date.
* No on-device transcription model is bundled: dictation uses the OS recogniser.
