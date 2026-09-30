# ADR 0003 - Static embeddings + bilingual ontology + FTS5 instead of a transformer

**Status:** accepted

**Context.** "Search by meaning" and auto-categorisation must work offline, instantly, in English and Italian, on
short notes, with a small app size.

**Decision.** Ship a 7.9 MB int8 static-embedding model (Model2Vec potion-base-8M), a hand-written concept
ontology (67 concepts, EN/IT), and SQLite FTS5; fuse the three signals (see AI_ENGINE.md).

**Evidence.** Measured on the sample corpus, the static model alone ranked an unrelated note above "milk and
eggs" for the query "groceries"; with the ontology the flagship example works, including cross-language
("spesa"). A transformer (tens to hundreds of MB, native runtime, tens of ms per note) would add cost and
still need a lexical layer for exactness.

**Consequences.** Everything is explainable (every result carries its reasons), sub-millisecond, and testable.
Quality depends on ontology coverage (measured ~80-85% category accuracy on unseen notes); the encoder is an
interface, so a larger or cloud model can replace the neural part without changing callers.
