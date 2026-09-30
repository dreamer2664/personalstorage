# ADR 0004 - Write first, enrich after

**Status:** accepted

**Decision.** `capture()` does only bounded, local work before returning (analysis ~1 ms, one transaction, index
update). Reminders, graph edges, link previews and re-analysis run on a serial background queue after commit.
The composer clears optimistically and restores the text if the write fails.

**Consequences.** Capture latency is independent of network, model size and library size; a killed app loses
nothing (enrichment is idempotent and `reindexStale()` resumes on launch); tests need `CaptureService.settle()`
to await post-commit work.
