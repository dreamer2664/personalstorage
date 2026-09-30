import 'package:drift/drift.dart';

import 'tables.dart';

part 'app_database.g.dart';

/// Local-first SQLite store (via drift). Reactive queries (`watch`) drive the UI; a background
/// isolate executes statements, so even bulk operations never block a frame.
///
/// Full-text search lives in an FTS5 virtual table (`notes_fts`) keyed by the notes' rowid and
/// maintained by `NoteRepository` inside the same transactions as the notes themselves.
@DriftDatabase(tables: [Notes, ChecklistItems, Attachments, Tags, NoteTags, Tasks, Embeddings, Edges])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _createFts();
      await _createIndexes();
    },
    onUpgrade: (m, from, to) async {
      // Add stepwise migrations here; never drop user data.
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await customStatement('PRAGMA journal_mode = WAL');
    },
  );

  Future<void> _createFts() => customStatement(
    "CREATE VIRTUAL TABLE IF NOT EXISTS notes_fts USING fts5(title, body, tags, "
    "tokenize = 'unicode61 remove_diacritics 2', prefix = '2 3')",
  );

  Future<void> _createIndexes() async {
    await customStatement('CREATE INDEX IF NOT EXISTS idx_notes_created ON notes (created_at DESC)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_notes_category ON notes (category_id)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_checklist_note ON checklist_items (note_id, position)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_attach_note ON attachments (note_id, position)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_tasks_due ON tasks (done, due_at)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_tasks_note ON tasks (note_id)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_notetags_tag ON note_tags (tag_id)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_edges_b ON edges (b)');
  }
}
