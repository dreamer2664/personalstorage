# ADR 0002 - Local-first storage with SQLite (drift) and FTS5

**Status:** accepted

**Decision.** All data lives in one SQLite file accessed through drift, with an FTS5 virtual table for full-text
search. IDs are ULIDs, deletes are soft, every table is reachable by one repository class.

**Why.** Offline by construction; typed, reactive queries (`watch()`) drive the UI; BM25 search and relational data
share a file and a transaction; drift gives migrations and a background isolate executor on mobile and WASM on
web. ULIDs + `updated_at` + tombstones make a later sync layer additive.

**Consequences.** Vectors are stored as BLOBs and searched in memory (brute force is exact and fast at personal
scale, see ARCHITECTURE.md); FTS rows are maintained in code (inside the same transaction) rather than by triggers
because they include tags and checklist text; generated `*.g.dart` files are committed and verified fresh in CI.
