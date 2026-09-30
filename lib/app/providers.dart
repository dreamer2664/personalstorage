import 'dart:async';
import 'dart:convert';

import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:neural_brain/neural_brain.dart';

import '../data/db/app_database.dart';
import '../data/repositories/note_repository.dart';
import '../domain/models.dart';
import '../services/brain_service.dart';
import '../services/capture_service.dart';
import '../services/enrichment_service.dart';
import '../services/graph_service.dart';
import '../services/launch_actions.dart';
import '../services/link_preview_service.dart';
import '../services/media_store.dart';
import '../services/reminders.dart';
import '../services/search_service.dart';
import '../services/settings.dart';
import '../services/voice_service.dart';

const String kModelAsset = 'assets/models/potion-base-8m.psm';

/// The SQLite database. Overridden with an in-memory database in tests.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase(
    driftDatabase(
      name: 'personalstorage',
      web: DriftWebOptions(sqlite3Wasm: Uri.parse('sqlite3.wasm'), driftWorker: Uri.parse('drift_worker.js')),
    ),
  );
  ref.onDispose(db.close);
  return db;
});

final repositoryProvider = Provider<NoteRepository>((ref) => NoteRepository(ref.watch(databaseProvider)));

final mediaStoreProvider = Provider<MediaStore>((_) => FileMediaStore());

final remindersProvider = Provider<Reminders>((_) => kIsWeb ? NoReminders() : LocalNotificationReminders());

final httpClientProvider = Provider<http.Client>((ref) {
  final c = http.Client();
  ref.onDispose(c.close);
  return c;
});

/// Dictation engine; widgets listen to it with a `ListenableBuilder`.
final voiceServiceProvider = Provider<VoiceService>((ref) {
  final v = VoiceService();
  ref.onDispose(v.dispose);
  return v;
});

/// Loads the model bytes; replaced in tests.
final modelBytesProvider = Provider<Future<Uint8List> Function()>((_) => () async {
      final data = await rootBundle.load(kModelAsset);
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    });

/// Secret storage for the optional cloud-embeddings API key.
class SecretsStore {
  SecretsStore([FlutterSecureStorage? storage]) : _s = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _s;
  static const _key = 'cloud_api_key';

  Future<String?> read() async {
    try {
      return await _s.read(key: _key);
    } on Object {
      return null;
    }
  }

  Future<void> write(String? value) async {
    try {
      if (value == null || value.isEmpty) {
        await _s.delete(key: _key);
      } else {
        await _s.write(key: _key, value: value);
      }
    } on Object catch (e) {
      debugPrint('Secure storage unavailable: $e');
    }
  }
}

final secretsProvider = Provider<SecretsStore>((_) => SecretsStore());

/// Bundle of every long-lived service, created once after the brain is loaded.
class AppServices {
  AppServices({
    required this.db,
    required this.repo,
    required this.brain,
    required this.enrichment,
    required this.capture,
    required this.search,
    required this.graph,
    required this.reminders,
    required this.media,
  });

  final AppDatabase db;
  final NoteRepository repo;
  final BrainService brain;
  final EnrichmentService enrichment;
  final CaptureService capture;
  final SearchService search;
  final GraphService graph;
  final Reminders reminders;
  final MediaStore media;

  Ontology get ontology => brain.brain.ontology;
}

/// Assembles the app. The UI shows a brief splash until this completes (tens of milliseconds:
/// decoding the 8 MB model asset and loading stored vectors).
final appServicesProvider = FutureProvider<AppServices>((ref) async {
  final db = ref.watch(databaseProvider);
  final repo = ref.watch(repositoryProvider);
  final reminders = ref.watch(remindersProvider);
  final media = ref.watch(mediaStoreProvider);
  final settings = ref.read(settingsProvider);

  // Optional cloud embeddings (opt-in): replaces the retrieval vector space, never the local one.
  TextEncoder? cloud;
  if (settings.cloudEmbeddings) {
    final key = await ref.read(secretsProvider).read();
    if (key != null && key.isNotEmpty) {
      final client = ref.read(httpClientProvider);
      cloud = CloudTextEncoder(
        baseUrl: Uri.parse(settings.cloudBaseUrl),
        apiKey: key,
        model: settings.cloudModel,
        dim: settings.cloudDim,
        post: (url, headers, body) async {
          final r = await client.post(url, headers: headers, body: jsonEncode(body)).timeout(const Duration(seconds: 20));
          if (r.statusCode >= 400) throw StateError('Embedding provider error ${r.statusCode}');
          return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, Object?>;
        },
      );
    }
  }

  final brain = await BrainService.load(ref.read(modelBytesProvider), retrievalEncoder: cloud);
  await brain.hydrate(repo);

  int hour() => ref.read(settingsProvider).reminderHour;
  final enrichment = EnrichmentService(
    repo: repo,
    brain: brain,
    reminders: reminders,
    links: LinkPreviewService(ref.read(httpClientProvider)),
    fetchPreviews: () => ref.read(settingsProvider).fetchLinkPreviews,
    reminderHour: hour,
  );
  final capture = CaptureService(repo: repo, brain: brain, enrichment: enrichment, reminders: reminders, media: media, reminderHour: hour);

  await reminders.init(onOpenNote: (id) => ref.read(launchRequestProvider.notifier).fire(LaunchActionType.openNote, noteId: id));
  unawaited(LaunchActions(ref).attach());

  // Background housekeeping after the first frame: re-embed stale notes, refresh reminders.
  unawaited(Future<void>.delayed(const Duration(milliseconds: 400), () async {
    await enrichment.reindexStale();
    await reminders.syncAll(await repo.openTasksWithReminders(), hour: hour());
    await repo.purgeDeletedBefore(DateTime.now().subtract(const Duration(days: 30)));
  }));

  return AppServices(
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
});

// ─────────────────────────── reactive data for the UI ───────────────────────────

/// Library filter: a category (domain id) and/or a tag.
@immutable
class LibraryFilter {
  const LibraryFilter({this.categoryId, this.tag});

  final String? categoryId;
  final String? tag;

  @override
  bool operator ==(Object other) => other is LibraryFilter && other.categoryId == categoryId && other.tag == tag;

  @override
  int get hashCode => Object.hash(categoryId, tag);
}

class LibraryFilterNotifier extends Notifier<LibraryFilter> {
  @override
  LibraryFilter build() => const LibraryFilter();

  void set(LibraryFilter f) => state = f;
}

final libraryFilterProvider = NotifierProvider<LibraryFilterNotifier, LibraryFilter>(LibraryFilterNotifier.new);

final summariesProvider = StreamProvider<List<NoteSummary>>((ref) {
  final repo = ref.watch(repositoryProvider);
  final f = ref.watch(libraryFilterProvider);
  return repo.watchSummaries(categoryId: f.categoryId, tag: f.tag);
});

final recentSummariesProvider = StreamProvider<List<NoteSummary>>((ref) => ref.watch(repositoryProvider).watchSummaries(limit: 4));

final noteDetailProvider = StreamProvider.family<NoteDetail?, String>((ref, id) => ref.watch(repositoryProvider).watchNote(id));

final tasksProvider = StreamProvider<List<TaskInfo>>((ref) => ref.watch(repositoryProvider).watchTasks());

final categoryCountsProvider = StreamProvider<Map<String?, int>>((ref) => ref.watch(repositoryProvider).watchCategoryCounts());

final noteCountProvider = StreamProvider<int>((ref) => ref.watch(repositoryProvider).watchNoteCount());

/// Stored edges; the graph screen re-loads when they change.
final edgesProvider = StreamProvider<List<StoredEdge>>((ref) => ref.watch(repositoryProvider).watchEdges());
