import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:personalstorage/app/providers.dart';
import 'package:personalstorage/data/db/app_database.dart';
import 'package:personalstorage/data/repositories/note_repository.dart';
import 'package:personalstorage/domain/models.dart';
import 'package:personalstorage/services/brain_service.dart';
import 'package:personalstorage/services/capture_service.dart';
import 'package:personalstorage/services/enrichment_service.dart';
import 'package:personalstorage/services/graph_service.dart';
import 'package:personalstorage/services/link_preview_service.dart';
import 'package:personalstorage/services/media_store.dart';
import 'package:personalstorage/services/reminders.dart';
import 'package:personalstorage/services/search_service.dart';

/// Records scheduled reminders instead of touching the OS.
class FakeReminders implements Reminders {
  final Map<String, TaskInfo> scheduled = {};
  final List<String> cancelled = [];

  @override
  Future<void> init({void Function(String noteId)? onOpenNote}) async {}
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> schedule(TaskInfo task, {int hour = 9}) async => scheduled[task.id] = task;
  @override
  Future<void> cancel(String taskId) async {
    scheduled.remove(taskId);
    cancelled.add(taskId);
  }

  @override
  Future<void> syncAll(List<TaskInfo> openTasks, {int hour = 9}) async {
    for (final t in openTasks) {
      await schedule(t);
    }
  }
}

class FakeMedia implements MediaStore {
  final List<String> deleted = [];
  @override
  Future<String> persistImage(String sourcePath) async => 'persisted/$sourcePath';
  @override
  Future<void> delete(String path) async => deleted.add(path);
}

/// A fully wired service graph on an in-memory database, with the real bundled model.
class Harness {
  Harness._(this.services, this.reminders, this.media);

  final AppServices services;
  final FakeReminders reminders;
  final FakeMedia media;

  NoteRepository get repo => services.repo;
  CaptureService get capture => services.capture;
  SearchService get search => services.search;
  EnrichmentService get enrichment => services.enrichment;

  static Future<Harness> create({http.Client? httpClient, bool fetchPreviews = true}) async {
    final db = AppDatabase(NativeDatabase.memory());
    final repo = NoteRepository(db);
    final brain = await BrainService.load(() async => Uint8List.fromList(File('assets/models/potion-base-8m.psm').readAsBytesSync()));
    final reminders = FakeReminders();
    final media = FakeMedia();
    final enrichment = EnrichmentService(
      repo: repo,
      brain: brain,
      reminders: reminders,
      links: LinkPreviewService(httpClient ?? MockClient((_) async => http.Response('', 404))),
      fetchPreviews: () => fetchPreviews,
      reminderHour: () => 9,
    );
    final capture = CaptureService(repo: repo, brain: brain, enrichment: enrichment, reminders: reminders, media: media, reminderHour: () => 9);
    final services = AppServices(
      db: db,
      repo: repo,
      brain: brain,
      enrichment: enrichment,
      capture: capture,
      search: SearchService(repo: repo, brain: brain),
      graph: GraphService(repo),
      reminders: reminders,
      media: media,
    );
    return Harness._(services, reminders, media);
  }

  /// Captures [text] and waits for the enrichment queue to drain.
  Future<String> note(String text, {DateTime? at, List<String> images = const [], bool checklist = false}) async {
    final r = await capture.capture(CaptureDraft(text: text, createdAt: at, imagePaths: images, acceptChecklistSuggestion: checklist));
    await capture.settle();
    return r!.noteId;
  }

  Future<void> dispose() async {
    await capture.settle();
    await services.db.close();
  }

  @visibleForTesting
  static DateTime get fixedNow => DateTime(2026, 9, 30, 10);
}
