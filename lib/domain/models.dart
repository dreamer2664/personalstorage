import 'package:flutter/foundation.dart';
import 'package:neural_brain/neural_brain.dart';

/// A tag attached to a note.
@immutable
class TagInfo {
  const TagInfo(this.name, this.source, [this.confidence = 1.0]);

  final String name;

  /// `user` or `ai`.
  final String source;
  final double confidence;

  bool get isUser => source == 'user';
}

@immutable
class ChecklistEntry {
  const ChecklistEntry({required this.id, required this.label, required this.checked, required this.position});

  final String id;
  final String label;
  final bool checked;
  final int position;
}

enum AttachmentKind { image, link }

@immutable
class AttachmentInfo {
  const AttachmentInfo({
    required this.id,
    required this.kind,
    required this.uri,
    this.title,
    this.description,
    this.imageUrl,
    this.host,
  });

  final String id;
  final AttachmentKind kind;

  /// Local file path (image) or URL (link).
  final String uri;
  final String? title;
  final String? description;
  final String? imageUrl;
  final String? host;
}

@immutable
class TaskInfo {
  const TaskInfo({
    required this.id,
    required this.noteId,
    required this.title,
    required this.done,
    this.dueAt,
    this.hasTime = false,
    this.isDeadline = false,
    this.priority = 0,
    this.noteTitle,
    this.categoryId,
  });

  final String id;
  final String noteId;
  final String title;
  final bool done;
  final DateTime? dueAt;
  final bool hasTime;
  final bool isDeadline;
  final int priority;

  /// Title of the source note (filled by the tasks query).
  final String? noteTitle;
  final String? categoryId;

  /// When a reminder should fire (all-day items remind at 09:00).
  DateTime? get remindAt {
    final d = dueAt;
    if (d == null) return null;
    return hasTime ? d : DateTime(d.year, d.month, d.day, 9);
  }

  bool isOverdue(DateTime now) => !done && dueAt != null && (hasTime ? dueAt!.isBefore(now) : dueAt!.isBefore(DateTime(now.year, now.month, now.day)));
}

/// Compact projection of a note for lists.
@immutable
class NoteSummary {
  const NoteSummary({
    required this.id,
    required this.title,
    required this.snippet,
    required this.kind,
    required this.priority,
    required this.pinned,
    required this.createdAt,
    required this.updatedAt,
    required this.tags,
    required this.openTasks,
    required this.checklistTotal,
    required this.checklistDone,
    required this.imageUris,
    required this.source,
    this.categoryId,
    this.nextDue,
    this.nextDueHasTime = false,
    this.linkHost,
  });

  final String id;
  final String title;
  final String snippet;
  final NoteKind kind;
  final String? categoryId;
  final int priority;
  final bool pinned;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<TagInfo> tags;
  final int openTasks;
  final DateTime? nextDue;
  final bool nextDueHasTime;
  final int checklistTotal;
  final int checklistDone;
  final List<String> imageUris;
  final String? linkHost;
  final String source;
}

/// Everything about one note, for the detail screen.
@immutable
class NoteDetail {
  const NoteDetail({
    required this.id,
    required this.title,
    required this.body,
    required this.kind,
    required this.priority,
    required this.pinned,
    required this.categoryLocked,
    required this.priorityLocked,
    required this.language,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
    required this.tags,
    required this.checklist,
    required this.attachments,
    required this.tasks,
    this.categoryId,
  });

  final String id;
  final String title;
  final String body;
  final NoteKind kind;
  final String? categoryId;
  final int priority;
  final bool pinned;
  final bool categoryLocked;
  final bool priorityLocked;
  final String language;
  final String source;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<TagInfo> tags;
  final List<ChecklistEntry> checklist;
  final List<AttachmentInfo> attachments;
  final List<TaskInfo> tasks;

  List<AttachmentInfo> get images => attachments.where((a) => a.kind == AttachmentKind.image).toList();
  List<AttachmentInfo> get links => attachments.where((a) => a.kind == AttachmentKind.link).toList();
}

/// Payload for creating a note in one transaction (produced by the capture pipeline).
@immutable
class NewNote {
  const NewNote({
    required this.id,
    required this.body,
    required this.title,
    required this.kind,
    required this.priority,
    required this.language,
    required this.source,
    required this.createdAt,
    required this.tags,
    required this.checklist,
    required this.imagePaths,
    required this.links,
    required this.tasks,
    this.categoryId,
    this.embedding,
  });

  final String id;
  final String body;
  final String title;
  final NoteKind kind;
  final String? categoryId;
  final int priority;
  final String language;
  final String source;
  final DateTime createdAt;
  final List<TagSuggestion> tags;
  final List<ChecklistItemDraft> checklist;
  final List<String> imagePaths;
  final List<ExtractedUrl> links;
  final List<ExtractedAction> tasks;
  final EmbeddingPayload? embedding;
}

/// What is stored per note to make it searchable.
@immutable
class EmbeddingPayload {
  const EmbeddingPayload({
    required this.modelId,
    required this.vector,
    required this.conceptsJson,
    required this.words,
    required this.stems,
    required this.keywords,
    required this.ontologyVersion,
  });

  final String modelId;
  final Float32List vector;
  final String conceptsJson;
  final List<String> words;
  final List<String> stems;
  final List<String> keywords;
  final int ontologyVersion;
}

/// A stored edge.
@immutable
class StoredEdge {
  const StoredEdge(this.a, this.b, this.weight, this.kind, this.reason);

  final String a;
  final String b;
  final double weight;
  final String kind;
  final String? reason;
}

/// A node candidate for the graph.
@immutable
class GraphNoteRow {
  const GraphNoteRow({
    required this.id,
    required this.title,
    required this.priority,
    required this.pinned,
    required this.tags,
    this.categoryId,
  });

  final String id;
  final String title;
  final String? categoryId;
  final int priority;
  final bool pinned;
  final List<String> tags;
}
