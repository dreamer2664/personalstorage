# Changelog

## 1.0.0

First complete version.

**Capture** - always-ready composer (autofocus, resume-to-capture), live insight chips, optimistic save with
Undo, voice dictation (on-device preferred), photo attachments with collage, links with previews, checklists
(auto-detected or suggested), share-sheet capture on Android.

**Neural Brain (on-device, offline)** - EN/IT date and action extraction (tasks with deadlines and reminders),
bilingual concept ontology (67 concepts), static-embedding model (7.9 MB int8), hybrid semantic search with
"why matched", auto category/tags/priority, related notes, optional OpenAI-compatible cloud embeddings.

**Knowledge graph** - force-directed (Barnes-Hut) interactive graph with clusters, pinch/pan/drag, tap-to-open,
cluster sheets, connection-strength slider, tag hubs.

**One-tap entry points** - deep links, Android Quick Settings tile / widget / shortcuts, iOS lock-screen widgets
and iOS 18 controls (opt-in target), iOS quick actions.

**Engineering** - Flutter + drift/SQLite/FTS5 + Riverpod, pure-Dart `neural_brain` package, 220+ tests, CI for
format/analyze/test and web/Android/iOS builds (incl. the Swift widget extension), ADRs and architecture docs.
