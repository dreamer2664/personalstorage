import 'package:drift/drift.dart';

/// A captured note. Everything else hangs off [Notes.id] (a sortable ULID).
///
/// Soft delete ([deletedAt]) powers "Undo" and a 30-day trash; `*Locked` flags record that the
/// user overrode an AI decision, so re-analysis never fights the user.
@DataClassName('NoteRow')
class Notes extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get body => text().withDefault(const Constant(''))();

  /// `text` | `checklist` | `link` | `image` (see `NoteKind` in neural_brain).
  TextColumn get kind => text().withDefault(const Constant('text'))();

  /// Ontology *domain* id (e.g. `finance`), null = uncategorised.
  TextColumn get categoryId => text().nullable()();
  IntColumn get priority => integer().withDefault(const Constant(0))();
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  BoolColumn get titleLocked => boolean().withDefault(const Constant(false))();
  BoolColumn get categoryLocked => boolean().withDefault(const Constant(false))();
  BoolColumn get priorityLocked => boolean().withDefault(const Constant(false))();
  TextColumn get language => text().withDefault(const Constant('und'))();

  /// `typed` | `voice` | `share` | `widget` | `sample` | `import`.
  TextColumn get source => text().withDefault(const Constant('typed'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('ChecklistRow')
class ChecklistItems extends Table {
  TextColumn get id => text()();
  TextColumn get noteId => text().references(Notes, #id, onDelete: KeyAction.cascade)();
  TextColumn get label => text()();
  BoolColumn get checked => boolean().withDefault(const Constant(false))();
  IntColumn get position => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Images (local files) and links (URL + fetched preview metadata).
@DataClassName('AttachmentRow')
class Attachments extends Table {
  TextColumn get id => text()();
  TextColumn get noteId => text().references(Notes, #id, onDelete: KeyAction.cascade)();

  /// `image` | `link`.
  TextColumn get kind => text()();

  /// File path (image) or URL (link).
  TextColumn get uri => text()();
  TextColumn get title => text().nullable()();
  TextColumn get description => text().nullable()();
  TextColumn get imageUrl => text().nullable()();
  TextColumn get host => text().nullable()();
  IntColumn get position => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('TagRow')
class Tags extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().unique()();
}

/// Note <-> tag link with provenance: `user` tags are never removed by re-analysis.
@DataClassName('NoteTagRow')
class NoteTags extends Table {
  TextColumn get noteId => text().references(Notes, #id, onDelete: KeyAction.cascade)();
  IntColumn get tagId => integer().references(Tags, #id, onDelete: KeyAction.cascade)();
  TextColumn get source => text().withDefault(const Constant('ai'))();
  RealColumn get confidence => real().withDefault(const Constant(1.0))();

  @override
  Set<Column<Object>> get primaryKey => {noteId, tagId};
}

/// Actions extracted from notes ("call mom tomorrow 5pm") or added by hand.
@DataClassName('TaskRow')
class Tasks extends Table {
  TextColumn get id => text()();
  TextColumn get noteId => text().references(Notes, #id, onDelete: KeyAction.cascade)();
  TextColumn get title => text()();
  DateTimeColumn get dueAt => dateTime().nullable()();
  BoolColumn get hasTime => boolean().withDefault(const Constant(false))();
  BoolColumn get isDeadline => boolean().withDefault(const Constant(false))();
  IntColumn get priority => integer().withDefault(const Constant(0))();
  BoolColumn get done => boolean().withDefault(const Constant(false))();
  DateTimeColumn get doneAt => dateTime().nullable()();

  /// `ai` = extracted (replaced on re-analysis), `user` = added/edited by hand (kept).
  TextColumn get origin => text().withDefault(const Constant('ai'))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// One retrieval vector per note plus its sparse concept activations. `modelId` and
/// `ontologyVersion` tell the enrichment queue when a note must be re-embedded.
@DataClassName('EmbeddingRow')
class Embeddings extends Table {
  TextColumn get noteId => text().references(Notes, #id, onDelete: KeyAction.cascade)();
  TextColumn get modelId => text()();
  IntColumn get dim => integer()();
  BlobColumn get vector => blob()();
  TextColumn get conceptsJson => text().withDefault(const Constant('{}'))();
  TextColumn get wordsJson => text().withDefault(const Constant('[]'))();
  TextColumn get stemsJson => text().withDefault(const Constant('[]'))();
  TextColumn get keywordsJson => text().withDefault(const Constant('[]'))();
  IntColumn get ontologyVersion => integer()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {noteId};
}

/// Undirected, AI-discovered (or explicit) connections between notes; `a < b` by construction.
@DataClassName('EdgeRow')
class Edges extends Table {
  @ReferenceName('edgesAsA')
  TextColumn get a => text().references(Notes, #id, onDelete: KeyAction.cascade)();
  @ReferenceName('edgesAsB')
  TextColumn get b => text().references(Notes, #id, onDelete: KeyAction.cascade)();

  /// `semantic` | `link`.
  TextColumn get kind => text().withDefault(const Constant('semantic'))();
  RealColumn get weight => real()();
  TextColumn get reason => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {a, b, kind};
}
