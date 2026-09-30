import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:neural_brain/neural_brain.dart';

import '../core/util/ulid.dart';
import '../data/repositories/note_repository.dart';
import '../domain/models.dart';
import 'brain_service.dart';
import 'enrichment_service.dart';
import 'media_store.dart';
import 'reminders.dart';

/// What the user typed/dictated/attached, before analysis.
@immutable
class CaptureDraft {
  const CaptureDraft({
    this.text = '',
    this.imagePaths = const [],
    this.source = 'typed',
    this.acceptChecklistSuggestion = false,
    this.createdAt,
    this.referenceTime,
  });

  final String text;
  final List<String> imagePaths;

  /// `typed`, `voice`, `share`, `widget`, `sample`.
  final String source;

  /// The user tapped "Make checklist" on a low-confidence suggestion.
  final bool acceptChecklistSuggestion;
  final DateTime? createdAt;

  /// "Now" for resolving relative dates ("tomorrow", "Friday"). Defaults to [createdAt]: a note
  /// written last week saying "tomorrow" means *that* tomorrow. Demo data overrides it so its
  /// reminders land in the future.
  final DateTime? referenceTime;

  bool get isEmpty => text.trim().isEmpty && imagePaths.isEmpty;
}

class CaptureResult {
  const CaptureResult(this.noteId, this.analysis);

  final String noteId;
  final NoteAnalysis analysis;
}

/// The capture pipeline: **write first, enrich after**.
///
/// `capture` does only cheap, synchronous-ish work before returning - rule-based + static-model
/// analysis (~1 ms), one database transaction, an index update - so the note is on screen
/// immediately. Reminders, graph edges and link previews run afterwards on the enrichment queue.
class CaptureService {
  CaptureService({
    required this.repo,
    required this.brain,
    required this.enrichment,
    required this.reminders,
    required this.media,
    required this.reminderHour,
  });

  final NoteRepository repo;
  final BrainService brain;
  final EnrichmentService enrichment;
  final Reminders reminders;
  final MediaStore media;
  final int Function() reminderHour;

  Future<void> _afterCommitTail = Future.value();

  /// Completes when all post-commit work (reminders, edges, previews) of every capture so far
  /// has finished. The UI never awaits this; tests and "share then exit" flows do.
  Future<void> settle() async {
    await _afterCommitTail;
    await enrichment.idle();
  }

  /// Live, side-effect free preview used by the composer while typing.
  NoteAnalysis preview(String text, {int imageCount = 0, DateTime? now}) =>
      brain.brain.analyzeSync(text, now: now, imageCount: imageCount);

  Future<CaptureResult?> capture(CaptureDraft draft) async {
    if (draft.isEmpty) return null;
    final now = draft.createdAt ?? DateTime.now();
    final text = draft.text.trim();

    final analysis = await brain.brain.analyze(text, now: draft.referenceTime ?? now, imageCount: draft.imagePaths.length);
    final suggestion = analysis.checklistSuggestion;
    final makeChecklist = analysis.checklist == null && draft.acceptChecklistSuggestion && suggestion != null;
    final checklist = analysis.checklist ?? (makeChecklist ? suggestion : null);

    final images = <String>[];
    for (final path in draft.imagePaths) {
      images.add(await media.persistImage(path));
    }

    final id = Ulid.next(now);
    final kind = makeChecklist ? NoteKind.checklist : analysis.kind;
    final title = switch ((kind, makeChecklist)) {
      (NoteKind.checklist, true) => suggestion!.title ?? analysis.title,
      (NoteKind.image, _) when text.isEmpty => images.length == 1 ? 'Photo' : '${images.length} photos',
      _ => analysis.title,
    };

    await repo.insert(NewNote(
      id: id,
      body: text,
      title: title,
      kind: kind,
      categoryId: analysis.categoryId,
      priority: analysis.priority.level.value,
      language: analysis.language.code,
      source: draft.source,
      createdAt: now,
      tags: analysis.tags,
      checklist: checklist?.items ?? const [],
      imagePaths: images,
      links: analysis.entities.urls,
      tasks: analysis.actions,
      embedding: brain.payload(analysis),
    ));
    brain.index.upsert(IndexedNote.fromAnalysis(id, analysis, now));

    // Everything below happens after the note is already visible.
    _afterCommitTail = _afterCommitTail.then((_) => _afterCommit(id, analysis));
    unawaited(_afterCommitTail);
    return CaptureResult(id, analysis);
  }

  Future<void> _afterCommit(String id, NoteAnalysis analysis) async {
    try {
      if (analysis.actions.isNotEmpty) {
        final note = await repo.loadNote(id);
        for (final t in note?.tasks ?? const <TaskInfo>[]) {
          await reminders.schedule(t, hour: reminderHour());
        }
      }
    } on Object catch (e) {
      debugPrint('Scheduling reminders failed: $e');
    }
    await enrichment.onNoteCaptured(id);
  }
}
