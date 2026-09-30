import '../app/providers.dart';
import '../domain/models.dart';

/// User-level operations that touch several subsystems at once (database, search index,
/// reminders, graph edges). Keeping them here stops screens from knowing about those details.
class NoteActions {
  NoteActions(this.services);

  final AppServices services;

  /// Soft-deletes a note (recoverable for 30 days) and cleans up derived state.
  Future<void> delete(String noteId) async {
    final note = await services.repo.loadNote(noteId);
    await services.repo.softDelete(noteId);
    services.brain.index.remove(noteId);
    for (final t in note?.tasks ?? const <TaskInfo>[]) {
      await services.reminders.cancel(t.id);
    }
  }

  /// Undo of [delete]: restores the note and re-derives its index entry, edges and reminders.
  Future<void> undelete(String noteId) async {
    await services.repo.restore(noteId);
    await services.enrichment.reanalyze(noteId);
  }

  Future<void> setTaskDone(String taskId, bool done) async {
    await services.repo.setTaskDone(taskId, done);
    if (done) {
      await services.reminders.cancel(taskId);
    } else {
      final t = await services.repo.taskById(taskId);
      if (t != null) await services.reminders.schedule(t);
    }
  }

  Future<void> reschedule(TaskInfo task, DateTime due, {bool hasTime = true}) async {
    await services.repo.setTaskDue(task.id, due, hasTime: hasTime);
    final t = await services.repo.taskById(task.id);
    if (t != null) await services.reminders.schedule(t);
  }

  Future<void> deleteTask(String taskId) async {
    await services.repo.deleteTask(taskId);
    await services.reminders.cancel(taskId);
  }

  Future<void> removeAttachment(String attachmentId) async {
    final path = await services.repo.removeAttachment(attachmentId);
    if (path != null) await services.media.delete(path);
  }
}
