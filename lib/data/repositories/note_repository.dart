import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:neural_brain/neural_brain.dart';

import '../../core/util/ulid.dart';
import '../../domain/models.dart';
import '../db/app_database.dart';

/// The only place that speaks SQL. Every multi-table mutation runs in one transaction, and the
/// FTS5 index is refreshed inside it, so the index can never disagree with the notes.
class NoteRepository {
  NoteRepository(this.db);

  final AppDatabase db;

  // ─────────────────────────────── create ───────────────────────────────

  /// Inserts a note with all its children atomically. The note is visible to every `watch`
  /// stream as soon as the transaction commits - capture never waits for enrichment.
  Future<void> insert(NewNote n) => db.transaction(() async {
        await db.into(db.notes).insert(NotesCompanion.insert(
              id: n.id,
              title: Value(n.title),
              body: Value(n.body),
              kind: Value(n.kind.name),
              categoryId: Value(n.categoryId),
              priority: Value(n.priority),
              language: Value(n.language),
              source: Value(n.source),
              createdAt: n.createdAt,
              updatedAt: n.createdAt,
            ));
        for (var i = 0; i < n.checklist.length; i++) {
          await db.into(db.checklistItems).insert(ChecklistItemsCompanion.insert(
                id: Ulid.next(),
                noteId: n.id,
                label: n.checklist[i].text,
                checked: Value(n.checklist[i].checked),
                position: i,
              ));
        }
        for (var i = 0; i < n.imagePaths.length; i++) {
          await db.into(db.attachments).insert(AttachmentsCompanion.insert(
                id: Ulid.next(),
                noteId: n.id,
                kind: 'image',
                uri: n.imagePaths[i],
                position: Value(i),
              ));
        }
        for (var i = 0; i < n.links.length; i++) {
          await db.into(db.attachments).insert(AttachmentsCompanion.insert(
                id: Ulid.next(),
                noteId: n.id,
                kind: 'link',
                uri: n.links[i].url,
                host: Value(n.links[i].host),
                position: Value(i),
              ));
        }
        for (final t in n.tags) {
          await _attachTag(n.id, t.name, t.source == TagSource.user ? 'user' : 'ai', t.confidence);
        }
        for (final a in n.tasks) {
          await _insertTask(n.id, a, n.createdAt);
        }
        if (n.embedding != null) await _upsertEmbedding(n.id, n.embedding!);
        await _refreshFts(n.id);
      });

  Future<void> _insertTask(String noteId, ExtractedAction a, DateTime createdAt, {bool done = false}) =>
      db.into(db.tasks).insert(TasksCompanion.insert(
            id: Ulid.next(),
            noteId: noteId,
            title: a.title,
            dueAt: Value(a.due),
            hasTime: Value(a.hasDueTime),
            isDeadline: Value(a.isDeadline),
            priority: Value(a.urgent ? 3 : 0),
            done: Value(done),
            createdAt: createdAt,
          ));

  Future<int> _tagId(String name) async {
    await db.into(db.tags).insert(TagsCompanion.insert(name: name), mode: InsertMode.insertOrIgnore);
    return (await (db.select(db.tags)..where((t) => t.name.equals(name))).getSingle()).id;
  }

  Future<void> _attachTag(String noteId, String name, String source, double confidence) async {
    final id = await _tagId(name);
    await db.into(db.noteTags).insert(
          NoteTagsCompanion.insert(noteId: noteId, tagId: id, source: Value(source), confidence: Value(confidence)),
          mode: InsertMode.insertOrReplace,
        );
  }

  // ─────────────────────────────── update ───────────────────────────────

  /// Applies a fresh analysis after the text changed (or on re-index): refreshes derived
  /// fields unless the user locked them, replaces AI tags/tasks, keeps user-made ones.
  Future<void> applyAnalysis(
    String id, {
    required String body,
    required NoteAnalysis analysis,
    required EmbeddingPayload embedding,
    DateTime? now,
  }) =>
      db.transaction(() async {
        final row = await (db.select(db.notes)..where((n) => n.id.equals(id))).getSingleOrNull();
        if (row == null) return;
        final at = now ?? DateTime.now();
        // Structure the user already has wins over what the text alone suggests.
        final checklistCount = (await (db.select(db.checklistItems)..where((c) => c.noteId.equals(id))).get()).length;
        final imageCount = (await (db.select(db.attachments)..where((a) => a.noteId.equals(id) & a.kind.equals('image'))).get()).length;
        final kind = checklistCount > 0
            ? NoteKind.checklist
            : imageCount > 0
                ? NoteKind.image
                : analysis.kind;
        final keepTitle = body.trim().isEmpty && imageCount > 0;
        await (db.update(db.notes)..where((n) => n.id.equals(id))).write(NotesCompanion(
          body: Value(body),
          title: keepTitle || row.titleLocked ? const Value.absent() : Value(analysis.title),
          kind: Value(kind.name),
          language: Value(analysis.language.code),
          categoryId: row.categoryLocked ? const Value.absent() : Value(analysis.categoryId),
          priority: row.priorityLocked ? const Value.absent() : Value(analysis.priority.level.value),
          updatedAt: Value(at),
        ));
        // AI tags are replaced; user tags are kept.
        await (db.delete(db.noteTags)..where((t) => t.noteId.equals(id) & t.source.equals('ai'))).go();
        for (final t in analysis.tags) {
          final exists = await (db.select(db.noteTags).join([innerJoin(db.tags, db.tags.id.equalsExp(db.noteTags.tagId))])
                ..where(db.noteTags.noteId.equals(id) & db.tags.name.equals(t.name)))
              .get();
          if (exists.isEmpty) await _attachTag(id, t.name, t.source == TagSource.user ? 'user' : 'ai', t.confidence);
        }
        // AI tasks are re-derived; completed ones stay completed when their title is unchanged.
        final old = await (db.select(db.tasks)..where((t) => t.noteId.equals(id) & t.origin.equals('ai'))).get();
        final doneTitles = {for (final t in old.where((t) => t.done)) t.title.toLowerCase()};
        await (db.delete(db.tasks)..where((t) => t.noteId.equals(id) & t.origin.equals('ai'))).go();
        for (final a in analysis.actions) {
          await _insertTask(id, a, at, done: doneTitles.contains(a.title.toLowerCase()));
        }
        await _upsertEmbedding(id, embedding);
        await _refreshFts(id);
      });

  /// Text edit from the detail screen: cheap write first; callers re-run analysis afterwards.
  Future<void> setBody(String id, String body) async {
    await (db.update(db.notes)..where((n) => n.id.equals(id))).write(NotesCompanion(body: Value(body), updatedAt: Value(DateTime.now())));
    await _refreshFts(id);
  }

  /// Sets the title. A title typed by the user ([lock] = true) survives re-analysis; clearing it
  /// hands control back to the AI (the next analysis derives a title again).
  Future<void> setTitle(String id, String title, {bool lock = false}) async {
    await (db.update(db.notes)..where((n) => n.id.equals(id))).write(NotesCompanion(
      title: Value(title),
      titleLocked: Value(lock && title.trim().isNotEmpty),
      updatedAt: Value(DateTime.now()),
    ));
    await _refreshFts(id);
  }

  /// Sets or clears (`null` = back to automatic) the category; a manual choice locks it.
  Future<void> setCategory(String id, String? categoryId) =>
      (db.update(db.notes)..where((n) => n.id.equals(id))).write(NotesCompanion(
        categoryId: Value(categoryId),
        categoryLocked: Value(categoryId != null),
        updatedAt: Value(DateTime.now()),
      ));

  Future<void> setPriority(String id, int? priority) =>
      (db.update(db.notes)..where((n) => n.id.equals(id))).write(NotesCompanion(
        priority: priority == null ? const Value.absent() : Value(priority),
        priorityLocked: Value(priority != null),
        updatedAt: Value(DateTime.now()),
      ));

  Future<void> setPinned(String id, bool pinned) =>
      (db.update(db.notes)..where((n) => n.id.equals(id))).write(NotesCompanion(pinned: Value(pinned)));

  Future<void> softDelete(String id) async {
    await (db.update(db.notes)..where((n) => n.id.equals(id))).write(NotesCompanion(deletedAt: Value(DateTime.now())));
    await db.customStatement('DELETE FROM notes_fts WHERE rowid = (SELECT rowid FROM notes WHERE id = ?)', [id]);
    await db.transaction(() async {
      await (db.delete(db.edges)..where((e) => e.a.equals(id) | e.b.equals(id))).go();
    });
  }

  Future<void> restore(String id) async {
    await (db.update(db.notes)..where((n) => n.id.equals(id))).write(const NotesCompanion(deletedAt: Value(null)));
    await _refreshFts(id);
  }

  Future<void> purgeDeletedBefore(DateTime cutoff) async {
    final ids = await (db.select(db.notes)..where((n) => n.deletedAt.isSmallerThanValue(cutoff))).map((r) => r.id).get();
    for (final id in ids) {
      await db.customStatement('DELETE FROM notes_fts WHERE rowid = (SELECT rowid FROM notes WHERE id = ?)', [id]);
      await (db.delete(db.notes)..where((n) => n.id.equals(id))).go();
    }
  }

  Future<void> deleteEverything() async {
    await db.transaction(() async {
      await db.customStatement('DELETE FROM notes_fts');
      for (final t in db.allTables) {
        await db.delete(t).go();
      }
    });
  }

  // ── tags
  Future<void> addUserTag(String noteId, String name) async {
    final n = name.trim().toLowerCase().replaceAll(RegExp(r'^#+'), '').replaceAll(RegExp(r'\s+'), '-');
    if (n.isEmpty) return;
    await _attachTag(noteId, n, 'user', 1.0);
    await _refreshFts(noteId);
  }

  Future<void> removeTag(String noteId, String name) async {
    final tag = await (db.select(db.tags)..where((t) => t.name.equals(name))).getSingleOrNull();
    if (tag == null) return;
    await (db.delete(db.noteTags)..where((t) => t.noteId.equals(noteId) & t.tagId.equals(tag.id))).go();
    await _refreshFts(noteId);
  }

  // ── checklist
  Future<void> setChecklistChecked(String itemId, bool checked) =>
      (db.update(db.checklistItems)..where((i) => i.id.equals(itemId))).write(ChecklistItemsCompanion(checked: Value(checked)));

  Future<void> addChecklistItem(String noteId, String label) async {
    final max = await (db.selectOnly(db.checklistItems)
          ..addColumns([db.checklistItems.position.max()])
          ..where(db.checklistItems.noteId.equals(noteId)))
        .map((r) => r.read(db.checklistItems.position.max()))
        .getSingle();
    await db.into(db.checklistItems).insert(ChecklistItemsCompanion.insert(
          id: Ulid.next(),
          noteId: noteId,
          label: label,
          position: (max ?? -1) + 1,
        ));
    await _refreshFts(noteId);
  }

  Future<void> removeChecklistItem(String noteId, String itemId) async {
    await (db.delete(db.checklistItems)..where((i) => i.id.equals(itemId))).go();
    await _refreshFts(noteId);
  }

  /// Converts a plain text note into a checklist (used by the "Make checklist" suggestion).
  Future<void> convertToChecklist(String noteId, List<ChecklistItemDraft> items, {String? title}) => db.transaction(() async {
        await (db.delete(db.checklistItems)..where((i) => i.noteId.equals(noteId))).go();
        for (var i = 0; i < items.length; i++) {
          await db.into(db.checklistItems).insert(ChecklistItemsCompanion.insert(
                id: Ulid.next(),
                noteId: noteId,
                label: items[i].text,
                checked: Value(items[i].checked),
                position: i,
              ));
        }
        await (db.update(db.notes)..where((n) => n.id.equals(noteId))).write(NotesCompanion(
          kind: Value(NoteKind.checklist.name),
          title: title == null ? const Value.absent() : Value(title),
          updatedAt: Value(DateTime.now()),
        ));
        await _refreshFts(noteId);
      });

  // ── attachments
  Future<void> addImages(String noteId, List<String> paths) => db.transaction(() async {
        final count = (await (db.select(db.attachments)..where((a) => a.noteId.equals(noteId))).get()).length;
        for (var i = 0; i < paths.length; i++) {
          await db.into(db.attachments).insert(AttachmentsCompanion.insert(
                id: Ulid.next(),
                noteId: noteId,
                kind: 'image',
                uri: paths[i],
                position: Value(count + i),
              ));
        }
        await (db.update(db.notes)..where((n) => n.id.equals(noteId))).write(NotesCompanion(
          kind: Value(NoteKind.image.name),
          updatedAt: Value(DateTime.now()),
        ));
      });

  Future<String?> removeAttachment(String attachmentId) async {
    final row = await (db.select(db.attachments)..where((a) => a.id.equals(attachmentId))).getSingleOrNull();
    if (row == null) return null;
    await (db.delete(db.attachments)..where((a) => a.id.equals(attachmentId))).go();
    await _refreshFts(row.noteId);
    return row.kind == 'image' ? row.uri : null;
  }

  Future<void> updateLinkPreview(String attachmentId, {String? title, String? description, String? imageUrl}) async {
    final row = await (db.select(db.attachments)..where((a) => a.id.equals(attachmentId))).getSingleOrNull();
    if (row == null) return;
    await (db.update(db.attachments)..where((a) => a.id.equals(attachmentId))).write(AttachmentsCompanion(
      title: Value(title),
      description: Value(description),
      imageUrl: Value(imageUrl),
    ));
    await _refreshFts(row.noteId);
  }

  Future<List<AttachmentRow>> linksWithoutPreview({int limit = 20}) =>
      (db.select(db.attachments)..where((a) => a.kind.equals('link') & a.title.isNull())..limit(limit)).get();

  // ── tasks
  Future<void> setTaskDone(String taskId, bool done) =>
      (db.update(db.tasks)..where((t) => t.id.equals(taskId))).write(TasksCompanion(
        done: Value(done),
        doneAt: Value(done ? DateTime.now() : null),
      ));

  Future<void> deleteTask(String taskId) => (db.delete(db.tasks)..where((t) => t.id.equals(taskId))).go();

  Future<String> addTask(String noteId, String title, {DateTime? due, bool hasTime = false}) async {
    final id = Ulid.next();
    await db.into(db.tasks).insert(TasksCompanion.insert(
          id: id,
          noteId: noteId,
          title: title,
          dueAt: Value(due),
          hasTime: Value(hasTime),
          origin: const Value('user'),
          createdAt: DateTime.now(),
        ));
    return id;
  }

  Future<void> setTaskDue(String taskId, DateTime? due, {bool hasTime = true}) =>
      (db.update(db.tasks)..where((t) => t.id.equals(taskId))).write(TasksCompanion(
        dueAt: Value(due),
        hasTime: Value(hasTime),
        origin: const Value('user'),
      ));

  Future<TaskInfo?> taskById(String id) async {
    final r = await (db.select(db.tasks)..where((t) => t.id.equals(id))).getSingleOrNull();
    return r == null ? null : _task(r);
  }

  // ─────────────────────────────── FTS ───────────────────────────────

  /// Rebuilds the FTS row of one note from the current database state.
  Future<void> _refreshFts(String id) async {
    final note = await (db.select(db.notes)..where((n) => n.id.equals(id))).getSingleOrNull();
    await db.customStatement('DELETE FROM notes_fts WHERE rowid = (SELECT rowid FROM notes WHERE id = ?)', [id]);
    if (note == null || note.deletedAt != null) return;
    final items = await (db.select(db.checklistItems)..where((i) => i.noteId.equals(id))..orderBy([(i) => OrderingTerm.asc(i.position)])).get();
    final links = await (db.select(db.attachments)..where((a) => a.noteId.equals(id) & a.kind.equals('link'))).get();
    final tagRows = await (db.select(db.noteTags).join([innerJoin(db.tags, db.tags.id.equalsExp(db.noteTags.tagId))])
          ..where(db.noteTags.noteId.equals(id)))
        .map((r) => r.read(db.tags.name)!)
        .get();
    final body = [
      note.body,
      ...items.map((i) => i.label),
      for (final l in links) ...[?l.title, ?l.description, ?l.host],
    ].join('\n');
    await db.customStatement(
      'INSERT INTO notes_fts(rowid, title, body, tags) VALUES ((SELECT rowid FROM notes WHERE id = ?), ?, ?, ?)',
      [id, note.title, body, tagRows.join(' ')],
    );
  }

  /// Normalised BM25 scores (0..1) for [query] over title/body/tags with prefix matching.
  Future<Map<String, double>> lexicalScores(String query, {int limit = 100}) async {
    final tokens = query
        .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
        .where((t) => t.length >= 2)
        .map((t) => '"${t.replaceAll('"', '""')}"*')
        .toList();
    if (tokens.isEmpty) return const {};
    final rows = await db.customSelect(
      'SELECT n.id AS id, bm25(notes_fts, 6.0, 1.0, 3.0) AS s FROM notes_fts '
      'JOIN notes n ON n.rowid = notes_fts.rowid '
      'WHERE notes_fts MATCH ?1 AND n.deleted_at IS NULL ORDER BY s LIMIT ?2',
      variables: [Variable.withString(tokens.join(' OR ')), Variable.withInt(limit)],
    ).get();
    return {
      for (final r in rows)
        r.read<String>('id'): () {
          // Matching is binary (>= 0.5); BM25 only ranks among matches. Raw BM25 collapses to ~0
          // in tiny libraries (IDF of a term present in every note), which must not hide a hit.
          final s = math.max(0.0, -r.read<double>('s'));
          return 0.5 + 0.5 * (s / (s + 3.0));
        }(),
    };
  }

  // ─────────────────────────────── embeddings / edges ───────────────────────────────

  Future<void> upsertEmbedding(String noteId, EmbeddingPayload p) => _upsertEmbedding(noteId, p);

  Future<void> _upsertEmbedding(String noteId, EmbeddingPayload p) => db.into(db.embeddings).insert(
        EmbeddingsCompanion.insert(
          noteId: noteId,
          modelId: p.modelId,
          dim: p.vector.length,
          vector: vectorToBytes(p.vector),
          conceptsJson: Value(p.conceptsJson),
          wordsJson: Value(jsonEncode(p.words)),
          stemsJson: Value(jsonEncode(p.stems)),
          keywordsJson: Value(jsonEncode(p.keywords)),
          ontologyVersion: p.ontologyVersion,
          updatedAt: DateTime.now(),
        ),
        mode: InsertMode.insertOrReplace,
      );

  /// Everything needed to rebuild the in-memory [SemanticIndex] at start-up.
  Future<List<StoredEmbedding>> loadEmbeddings() async {
    final rows = await (db.select(db.embeddings).join([
      innerJoin(db.notes, db.notes.id.equalsExp(db.embeddings.noteId)),
    ])..where(db.notes.deletedAt.isNull()))
        .get();
    final tagRows = await db.select(db.noteTags).join([innerJoin(db.tags, db.tags.id.equalsExp(db.noteTags.tagId))]).get();
    final tagsByNote = <String, Set<String>>{};
    for (final r in tagRows) {
      tagsByNote.putIfAbsent(r.readTable(db.noteTags).noteId, () => {}).add(r.readTable(db.tags).name);
    }
    return [
      for (final r in rows)
        StoredEmbedding(
          noteId: r.readTable(db.embeddings).noteId,
          modelId: r.readTable(db.embeddings).modelId,
          ontologyVersion: r.readTable(db.embeddings).ontologyVersion,
          vector: vectorFromBytes(r.readTable(db.embeddings).vector),
          conceptsJson: r.readTable(db.embeddings).conceptsJson,
          words: (jsonDecode(r.readTable(db.embeddings).wordsJson) as List<Object?>).cast<String>().toSet(),
          stems: (jsonDecode(r.readTable(db.embeddings).stemsJson) as List<Object?>).cast<String>().toSet(),
          keywords: (jsonDecode(r.readTable(db.embeddings).keywordsJson) as List<Object?>).cast<String>().toSet(),
          tags: tagsByNote[r.readTable(db.embeddings).noteId] ?? const {},
          categoryId: r.readTable(db.notes).categoryId,
          createdAt: r.readTable(db.notes).createdAt,
        ),
    ];
  }

  /// Ids of notes whose embedding is missing or was produced by another model/ontology.
  Future<List<NoteRow>> notesNeedingReindex(String modelId, int ontologyVersion) async {
    final rows = await db.customSelect(
      'SELECT n.id AS id FROM notes n LEFT JOIN embeddings e ON e.note_id = n.id '
      'WHERE n.deleted_at IS NULL AND (e.note_id IS NULL OR e.model_id != ?1 OR e.ontology_version != ?2) '
      'ORDER BY n.created_at DESC',
      variables: [Variable.withString(modelId), Variable.withInt(ontologyVersion)],
      readsFrom: {db.notes, db.embeddings},
    ).get();
    final ids = rows.map((r) => r.read<String>('id')).toList();
    if (ids.isEmpty) return const [];
    return (db.select(db.notes)..where((n) => n.id.isIn(ids))).get();
  }

  /// Replaces all *semantic* edges touching [noteId].
  Future<void> replaceEdges(String noteId, List<StoredEdge> edges) => db.transaction(() async {
        await (db.delete(db.edges)..where((e) => (e.a.equals(noteId) | e.b.equals(noteId)) & e.kind.equals('semantic'))).go();
        for (final e in edges) {
          final a = e.a.compareTo(e.b) < 0 ? e.a : e.b;
          final b = e.a.compareTo(e.b) < 0 ? e.b : e.a;
          await db.into(db.edges).insert(
                EdgesCompanion.insert(a: a, b: b, weight: e.weight, kind: Value(e.kind), reason: Value(e.reason)),
                mode: InsertMode.insertOrReplace,
              );
        }
      });

  Stream<List<StoredEdge>> watchEdges() => db.select(db.edges).watch().map((rows) => [
        for (final r in rows) StoredEdge(r.a, r.b, r.weight, r.kind, r.reason),
      ]);

  Future<List<StoredEdge>> edgesFor(String noteId) async {
    final rows = await (db.select(db.edges)..where((e) => e.a.equals(noteId) | e.b.equals(noteId))).get();
    return [for (final r in rows) StoredEdge(r.a, r.b, r.weight, r.kind, r.reason)];
  }

  // ─────────────────────────────── reads ───────────────────────────────

  Selectable<QueryRow> _trigger() => db.customSelect(
        'SELECT 1',
        readsFrom: {db.notes, db.noteTags, db.tags, db.tasks, db.checklistItems, db.attachments},
      );

  /// Notes for the library, newest first (pinned first). Re-emits on any relevant change.
  Stream<List<NoteSummary>> watchSummaries({String? categoryId, String? tag, int limit = 1000}) =>
      _trigger().watch().asyncMap((_) => loadSummaries(categoryId: categoryId, tag: tag, limit: limit));

  Future<List<NoteSummary>> loadSummaries({String? categoryId, String? tag, int limit = 1000, Set<String>? ids}) async {
    final q = db.select(db.notes)..where((n) => n.deletedAt.isNull());
    if (categoryId != null) q.where((n) => n.categoryId.equals(categoryId));
    if (ids != null) q.where((n) => n.id.isIn(ids));
    if (tag != null) {
      q.where((n) => n.id.isInQuery(db.selectOnly(db.noteTags).join([
            innerJoin(db.tags, db.tags.id.equalsExp(db.noteTags.tagId)),
          ])
            ..addColumns([db.noteTags.noteId])
            ..where(db.tags.name.equals(tag))));
    }
    q
      ..orderBy([(n) => OrderingTerm.desc(n.pinned), (n) => OrderingTerm.desc(n.createdAt)])
      ..limit(limit);
    final notes = await q.get();
    if (notes.isEmpty) return const [];
    final noteIds = notes.map((n) => n.id).toList();

    final tagRows = await (db.select(db.noteTags).join([innerJoin(db.tags, db.tags.id.equalsExp(db.noteTags.tagId))])
          ..where(db.noteTags.noteId.isIn(noteIds))
          ..orderBy([OrderingTerm.desc(db.noteTags.confidence)]))
        .get();
    final tags = <String, List<TagInfo>>{};
    for (final r in tagRows) {
      final nt = r.readTable(db.noteTags);
      tags.putIfAbsent(nt.noteId, () => []).add(TagInfo(r.readTable(db.tags).name, nt.source, nt.confidence));
    }
    for (final list in tags.values) {
      list.sort((a, b) => (b.isUser ? 1 : 0).compareTo(a.isUser ? 1 : 0));
    }

    final taskRows = await (db.select(db.tasks)..where((t) => t.noteId.isIn(noteIds) & t.done.equals(false))).get();
    final openTasks = <String, List<TaskRow>>{};
    for (final t in taskRows) {
      openTasks.putIfAbsent(t.noteId, () => []).add(t);
    }
    final checkRows = await (db.select(db.checklistItems)..where((c) => c.noteId.isIn(noteIds))).get();
    final checkTotal = <String, int>{}, checkDone = <String, int>{};
    for (final c in checkRows) {
      checkTotal[c.noteId] = (checkTotal[c.noteId] ?? 0) + 1;
      if (c.checked) checkDone[c.noteId] = (checkDone[c.noteId] ?? 0) + 1;
    }
    final attRows = await (db.select(db.attachments)
          ..where((a) => a.noteId.isIn(noteIds))
          ..orderBy([(a) => OrderingTerm.asc(a.position)]))
        .get();
    final images = <String, List<String>>{};
    final linkHost = <String, String>{};
    for (final a in attRows) {
      if (a.kind == 'image') {
        images.putIfAbsent(a.noteId, () => []).add(a.uri);
      } else {
        linkHost.putIfAbsent(a.noteId, () => a.host ?? a.uri);
      }
    }

    return [
      for (final n in notes)
        () {
          final open = openTasks[n.id] ?? const <TaskRow>[];
          final dated = open.where((t) => t.dueAt != null).toList()..sort((a, b) => a.dueAt!.compareTo(b.dueAt!));
          return NoteSummary(
            id: n.id,
            title: n.title.isEmpty ? 'Untitled' : n.title,
            snippet: _snippet(n.body, n.title),
            kind: NoteKind.parse(n.kind),
            categoryId: n.categoryId,
            priority: n.priority,
            pinned: n.pinned,
            createdAt: n.createdAt,
            updatedAt: n.updatedAt,
            tags: tags[n.id] ?? const [],
            openTasks: open.length,
            nextDue: dated.isEmpty ? null : dated.first.dueAt,
            nextDueHasTime: dated.isEmpty ? false : dated.first.hasTime,
            checklistTotal: checkTotal[n.id] ?? 0,
            checklistDone: checkDone[n.id] ?? 0,
            imageUris: images[n.id] ?? const [],
            linkHost: linkHost[n.id],
            source: n.source,
          );
        }(),
    ];
  }

  String _snippet(String body, String title) {
    var s = body.trim();
    if (title.isNotEmpty && s.toLowerCase().startsWith(title.toLowerCase())) s = s.substring(title.length).trim();
    s = s.replaceAll(RegExp(r'\s*\n+\s*'), ' · ').replaceAll(RegExp(r'^[-*•]\s*|\[[ xX]?\]\s*'), '');
    return s.length > 140 ? '${s.substring(0, 140)}…' : s;
  }

  Stream<NoteDetail?> watchNote(String id) =>
      _trigger().watch().asyncMap((_) => loadNote(id));

  Future<NoteDetail?> loadNote(String id) async {
    final n = await (db.select(db.notes)..where((r) => r.id.equals(id) & r.deletedAt.isNull())).getSingleOrNull();
    if (n == null) return null;
    final tagRows = await (db.select(db.noteTags).join([innerJoin(db.tags, db.tags.id.equalsExp(db.noteTags.tagId))])
          ..where(db.noteTags.noteId.equals(id))
          ..orderBy([OrderingTerm.desc(db.noteTags.confidence)]))
        .get();
    final items = await (db.select(db.checklistItems)..where((c) => c.noteId.equals(id))..orderBy([(c) => OrderingTerm.asc(c.position)])).get();
    final atts = await (db.select(db.attachments)..where((a) => a.noteId.equals(id))..orderBy([(a) => OrderingTerm.asc(a.position)])).get();
    final tasks = await (db.select(db.tasks)..where((t) => t.noteId.equals(id))..orderBy([(t) => OrderingTerm.asc(t.done), (t) => OrderingTerm.asc(t.dueAt)])).get();
    return NoteDetail(
      id: n.id,
      title: n.title,
      body: n.body,
      kind: NoteKind.parse(n.kind),
      categoryId: n.categoryId,
      priority: n.priority,
      pinned: n.pinned,
      categoryLocked: n.categoryLocked,
      priorityLocked: n.priorityLocked,
      titleLocked: n.titleLocked,
      language: n.language,
      source: n.source,
      createdAt: n.createdAt,
      updatedAt: n.updatedAt,
      tags: [
        for (final r in tagRows) TagInfo(r.readTable(db.tags).name, r.readTable(db.noteTags).source, r.readTable(db.noteTags).confidence),
      ],
      checklist: [for (final c in items) ChecklistEntry(id: c.id, label: c.label, checked: c.checked, position: c.position)],
      attachments: [
        for (final a in atts)
          AttachmentInfo(
            id: a.id,
            kind: a.kind == 'image' ? AttachmentKind.image : AttachmentKind.link,
            uri: a.uri,
            title: a.title,
            description: a.description,
            imageUrl: a.imageUrl,
            host: a.host,
          ),
      ],
      tasks: [for (final t in tasks) _task(t, noteTitle: n.title, categoryId: n.categoryId)],
    );
  }

  TaskInfo _task(TaskRow t, {String? noteTitle, String? categoryId}) => TaskInfo(
        id: t.id,
        noteId: t.noteId,
        title: t.title,
        done: t.done,
        dueAt: t.dueAt,
        hasTime: t.hasTime,
        isDeadline: t.isDeadline,
        priority: t.priority,
        noteTitle: noteTitle,
        categoryId: categoryId,
      );

  /// All tasks of live notes, open first, soonest due first.
  Stream<List<TaskInfo>> watchTasks() => (db.select(db.tasks).join([innerJoin(db.notes, db.notes.id.equalsExp(db.tasks.noteId))])
        ..where(db.notes.deletedAt.isNull())
        ..orderBy([OrderingTerm.asc(db.tasks.done), OrderingTerm.asc(db.tasks.dueAt), OrderingTerm.desc(db.tasks.createdAt)]))
      .watch()
      .map((rows) => [
            for (final r in rows)
              _task(r.readTable(db.tasks), noteTitle: r.readTable(db.notes).title, categoryId: r.readTable(db.notes).categoryId),
          ]);

  Future<List<TaskInfo>> openTasksWithReminders() async {
    final rows = await (db.select(db.tasks).join([innerJoin(db.notes, db.notes.id.equalsExp(db.tasks.noteId))])
          ..where(db.notes.deletedAt.isNull() & db.tasks.done.equals(false) & db.tasks.dueAt.isNotNull()))
        .get();
    return [for (final r in rows) _task(r.readTable(db.tasks), noteTitle: r.readTable(db.notes).title)];
  }

  /// `{categoryId: count}` for the library filter bar.
  Stream<Map<String?, int>> watchCategoryCounts() => db.customSelect(
        'SELECT category_id AS c, COUNT(*) AS n FROM notes WHERE deleted_at IS NULL GROUP BY category_id',
        readsFrom: {db.notes},
      ).watch().map((rows) => {for (final r in rows) r.readNullable<String>('c'): r.read<int>('n')});

  Stream<int> watchNoteCount() => db.customSelect('SELECT COUNT(*) AS n FROM notes WHERE deleted_at IS NULL', readsFrom: {db.notes}).watchSingle().map((r) => r.read<int>('n'));

  Future<int> noteCount() async =>
      (await db.customSelect('SELECT COUNT(*) AS n FROM notes WHERE deleted_at IS NULL', readsFrom: {db.notes}).getSingle()).read<int>('n');

  /// Nodes for the knowledge graph.
  Future<List<GraphNoteRow>> graphNotes() async {
    final notes = await (db.select(db.notes)..where((n) => n.deletedAt.isNull())).get();
    final tagRows = await db.select(db.noteTags).join([innerJoin(db.tags, db.tags.id.equalsExp(db.noteTags.tagId))]).get();
    final tags = <String, List<String>>{};
    for (final r in tagRows) {
      tags.putIfAbsent(r.readTable(db.noteTags).noteId, () => []).add(r.readTable(db.tags).name);
    }
    return [
      for (final n in notes)
        GraphNoteRow(
          id: n.id,
          title: n.title.isEmpty ? 'Untitled' : n.title,
          categoryId: n.categoryId,
          priority: n.priority,
          pinned: n.pinned,
          tags: tags[n.id] ?? const [],
        ),
    ];
  }

  /// Notes changed since they were last analysed - used by tests and diagnostics.
  Future<int> embeddingCount() async =>
      (await db.customSelect('SELECT COUNT(*) AS n FROM embeddings', readsFrom: {db.embeddings}).getSingle()).read<int>('n');

  // ─────────────────────────────── export ───────────────────────────────

  Future<Map<String, Object?>> exportAll() async {
    final notes = await (db.select(db.notes)..orderBy([(n) => OrderingTerm.asc(n.createdAt)])).get();
    final out = <Map<String, Object?>>[];
    for (final n in notes.where((n) => n.deletedAt == null)) {
      final d = await loadNote(n.id);
      if (d == null) continue;
      out.add({
        'id': d.id,
        'title': d.title,
        'body': d.body,
        'kind': d.kind.name,
        'category': d.categoryId,
        'priority': d.priority,
        'pinned': d.pinned,
        'createdAt': d.createdAt.toIso8601String(),
        'updatedAt': d.updatedAt.toIso8601String(),
        'tags': [for (final t in d.tags) t.name],
        'checklist': [for (final c in d.checklist) {'label': c.label, 'checked': c.checked}],
        'links': [for (final l in d.links) {'url': l.uri, 'title': l.title}],
        'images': [for (final i in d.images) i.uri],
        'tasks': [
          for (final t in d.tasks) {'title': t.title, 'due': t.dueAt?.toIso8601String(), 'done': t.done},
        ],
      });
    }
    return {'app': 'personalstorage', 'version': 1, 'exportedAt': DateTime.now().toIso8601String(), 'notes': out};
  }

  /// A Markdown rendering of all notes (for Obsidian-style vaults).
  Future<String> exportMarkdown() async {
    final data = await exportAll();
    final sb = StringBuffer('# Personal Storage export\n\n');
    for (final n in (data['notes']! as List<Object?>).cast<Map<String, Object?>>()) {
      sb.writeln('## ${n['title']}');
      final tags = (n['tags']! as List<Object?>).cast<String>();
      if (tags.isNotEmpty) sb.writeln(tags.map((t) => '#$t').join(' '));
      sb.writeln('\n${n['body']}\n');
      for (final c in (n['checklist']! as List<Object?>).cast<Map<String, Object?>>()) {
        sb.writeln('- [${c['checked'] == true ? 'x' : ' '}] ${c['label']}');
      }
      sb.writeln('\n---\n');
    }
    return sb.toString();
  }
}

/// A persisted embedding joined with what the index needs about its note.
class StoredEmbedding {
  const StoredEmbedding({
    required this.noteId,
    required this.modelId,
    required this.ontologyVersion,
    required this.vector,
    required this.conceptsJson,
    required this.words,
    required this.stems,
    required this.keywords,
    required this.tags,
    required this.createdAt,
    this.categoryId,
  });

  final String noteId;
  final String modelId;
  final int ontologyVersion;
  final Float32List vector;
  final String conceptsJson;
  final Set<String> words;
  final Set<String> stems;
  final Set<String> keywords;
  final Set<String> tags;
  final String? categoryId;
  final DateTime createdAt;

  /// Rebuilds the in-memory index entry.
  IndexedNote toIndexed(Ontology ontology) {
    final activation = ConceptActivation.fromSparse(ontology, (jsonDecode(conceptsJson) as Map<String, Object?>));
    return IndexedNote(
      id: noteId,
      vector: vector,
      concepts: activation.unit(),
      stems: stems,
      words: words,
      keywords: keywords,
      tags: tags,
      categoryId: categoryId,
      createdAt: createdAt,
    );
  }
}

/// Convenience used by repository callers to cap text lengths consistently.
String clip(String s, int max) => s.length <= max ? s : '${s.substring(0, math.max(0, max - 1))}…';
