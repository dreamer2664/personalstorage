import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:neural_brain/neural_brain.dart';

import '../data/repositories/note_repository.dart';
import '../domain/models.dart';
import 'brain_service.dart';
import 'link_preview_service.dart';
import 'reminders.dart';

/// Serial background queue for everything that must not delay capture: graph edges, link
/// previews, re-analysis after edits, and model/ontology migrations.
///
/// Jobs run strictly one after another (so SQLite writes never interleave) and yield to the UI
/// between batches. A failing job is logged and skipped - enrichment is best effort by design,
/// and is idempotent: anything missed is picked up by [reindexStale] on the next launch.
class EnrichmentService {
  EnrichmentService({
    required this.repo,
    required this.brain,
    required this.reminders,
    required this.links,
    required this.fetchPreviews,
    required this.reminderHour,
  });

  final NoteRepository repo;
  final BrainService brain;
  final Reminders reminders;
  final LinkPreviewService links;
  final bool Function() fetchPreviews;
  final int Function() reminderHour;

  /// Edges below this relatedness are not stored at all; the UI slider filters above it.
  static const double storeThreshold = 0.26;
  static const int edgesPerNote = 6;

  Future<void> _tail = Future.value();
  int _pending = 0;
  int get pending => _pending;

  /// Completes when everything queued so far has finished (used by tests).
  Future<void> idle() => _tail;

  Future<void> enqueue(String label, Future<void> Function() job) {
    _pending++;
    final run = _tail.then((_) => job()).catchError((Object e, StackTrace s) {
      debugPrint('Enrichment job "$label" failed: $e');
    }).whenComplete(() => _pending--);
    _tail = run;
    return run;
  }

  /// Called right after a note was saved.
  Future<void> onNoteCaptured(String noteId) => enqueue('captured:$noteId', () async {
        await refreshEdges(noteId);
        await _fetchPreviewsFor(noteId);
      });

  Future<void> refreshEdges(String noteId) async {
    final neighbors = brain.index.neighbors(noteId, k: edgesPerNote, minRelatedness: storeThreshold);
    await repo.replaceEdges(noteId, [
      for (final n in neighbors) StoredEdge(noteId, n.id, n.score, 'semantic', n.reasons.isEmpty ? null : n.reasons.first),
    ]);
  }

  Future<void> _fetchPreviewsFor(String noteId) async {
    if (!fetchPreviews()) return;
    final note = await repo.loadNote(noteId);
    if (note == null) return;
    var changed = false;
    for (final link in note.links.where((l) => l.title == null)) {
      final p = await links.fetch(link.uri);
      if (p == null || p.isEmpty) continue;
      await repo.updateLinkPreview(link.id, title: p.title, description: p.description, imageUrl: p.imageUrl);
      changed = true;
    }
    if (changed) await _reanalyze(noteId, retitleLinks: true);
  }

  /// Public entry point after a text edit. While the user is typing in a note, pass
  /// `convertToChecklist: false` so list-like text isn't restructured under their cursor.
  Future<void> reanalyze(String noteId, {bool convertToChecklist = true}) =>
      enqueue('reanalyze:$noteId', () => _reanalyze(noteId, convert: convertToChecklist));

  Future<void> _reanalyze(String noteId, {bool retitleLinks = false, bool convert = true}) async {
    final d = await repo.loadNote(noteId);
    if (d == null) return;
    final context = d.links
        .map((l) => [?l.title, ?l.description].join('. '))
        .where((s) => s.isNotEmpty)
        .join('\n');
    final a = await brain.brain.analyze(
      d.body,
      now: DateTime.now(),
      imageCount: d.images.length,
      context: context.isEmpty ? null : context,
      allowAutoChecklist: convert && d.checklist.isEmpty,
    );
    await repo.applyAnalysis(noteId, body: d.body, analysis: a, embedding: brain.payload(a));
    if (a.checklist != null && d.checklist.isEmpty && convert) {
      await repo.convertToChecklist(noteId, a.checklist!.items, title: a.checklist!.title);
    }
    final firstLinkTitle = d.links.map((l) => l.title).whereType<String>().firstOrNull;
    if (retitleLinks && d.kind == NoteKind.link && firstLinkTitle != null && !d.titleLocked) {
      await repo.setTitle(noteId, firstLinkTitle);
    }
    brain.index.upsert(IndexedNote.fromAnalysis(noteId, a, d.createdAt));
    await refreshEdges(noteId);
    // Tasks were re-derived: refresh their reminders.
    final fresh = await repo.loadNote(noteId);
    for (final t in fresh?.tasks ?? const <TaskInfo>[]) {
      t.done ? await reminders.cancel(t.id) : await reminders.schedule(t, hour: reminderHour());
    }
  }

  /// Re-embeds notes whose vectors are missing or stem from another model/ontology version,
  /// and back-fills missing link previews. Runs in small batches so the UI stays smooth.
  Future<void> reindexStale() => enqueue('reindexStale', () async {
        final stale = await repo.notesNeedingReindex(brain.modelId, brain.ontologyVersion);
        var n = 0;
        for (final row in stale) {
          final d = await repo.loadNote(row.id);
          if (d == null) continue;
          final a = await brain.brain.analyze(d.body, now: DateTime.now(), imageCount: d.images.length, allowAutoChecklist: d.checklist.isEmpty);
          await repo.applyAnalysis(row.id, body: d.body, analysis: a, embedding: brain.payload(a));
          brain.index.upsert(IndexedNote.fromAnalysis(row.id, a, d.createdAt));
          if (++n % 20 == 0) await Future<void>.delayed(Duration.zero);
        }
        for (final row in stale) {
          await refreshEdges(row.id);
          if (++n % 20 == 0) await Future<void>.delayed(Duration.zero);
        }
        if (fetchPreviews()) {
          for (final att in await repo.linksWithoutPreview()) {
            await _fetchPreviewsFor(att.noteId);
          }
        }
      });
}
