import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neural_brain/neural_brain.dart';
import 'package:personalstorage/domain/models.dart';
import 'package:personalstorage/services/capture_service.dart';
import 'package:personalstorage/services/link_preview_service.dart';
import 'package:personalstorage/services/sample_data.dart';

import 'support/harness.dart';

/// Integration tests: real SQLite (FTS5), real model, real services - no UI.
void main() {
  late Harness h;

  setUp(() async => h = await Harness.create());
  tearDown(() => h.dispose());

  group('capture', () {
    test('"milk and eggs" is saved, categorised, tagged and indexed without any input', () async {
      final id = await h.note('milk and eggs');
      final n = (await h.repo.loadNote(id))!;
      expect(n.body, 'milk and eggs');
      expect(n.kind, NoteKind.text);
      expect(n.categoryId, 'shopping');
      expect(n.tags.map((t) => t.name), contains('groceries'));
      expect(h.services.brain.index.contains(id), isTrue);
      expect(await h.repo.embeddingCount(), 1);
    });

    test('"remind me to buy X tomorrow" becomes a task with a deadline and a reminder', () async {
      final now = DateTime.now();
      final id = await h.note('Remind me to buy oat milk tomorrow at 5pm', at: now);
      final n = (await h.repo.loadNote(id))!;
      expect(n.tasks, hasLength(1));
      final t = n.tasks.single;
      expect(t.title, 'Buy oat milk');
      expect(t.dueAt, DateTime(now.year, now.month, now.day + 1, 17));
      expect(t.hasTime, isTrue);
      expect(h.reminders.scheduled.keys, contains(t.id));
    });

    test('shopping phrases become checklists; suggestions are opt-in', () async {
      final auto = (await h.repo.loadNote(await h.note('Buy bread, pasta and tomatoes')))!;
      expect(auto.kind, NoteKind.checklist);
      expect(auto.checklist.map((c) => c.label), ['Bread', 'Pasta', 'Tomatoes']);

      final plain = (await h.repo.loadNote(await h.note('milk and eggs')))!;
      expect(plain.checklist, isEmpty);

      final accepted = (await h.repo.loadNote(await h.note('milk and eggs', checklist: true)))!;
      expect(accepted.kind, NoteKind.checklist);
      expect(accepted.checklist.map((c) => c.label), ['Milk', 'Eggs']);
    });

    test('image notes keep persisted copies and get a readable title', () async {
      final id = await h.note('', images: ['/tmp/a.jpg', '/tmp/b.jpg']);
      final n = (await h.repo.loadNote(id))!;
      expect(n.kind, NoteKind.image);
      expect(n.title, '2 photos');
      expect(n.images.map((i) => i.uri), ['persisted//tmp/a.jpg', 'persisted//tmp/b.jpg']);
    });

    test('empty drafts are ignored', () async {
      expect(await h.capture.capture(const CaptureDraft(text: '   ')), isNull);
      expect(await h.repo.noteCount(), 0);
    });

    test('capture returns before enrichment finishes (write-first)', () async {
      final sw = Stopwatch()..start();
      await h.capture.capture(const CaptureDraft(text: 'Fix the login bug in the mobile app'));
      final captureMs = sw.elapsedMilliseconds;
      await h.capture.settle();
      // ignore: avoid_print
      print('capture() returned in ${captureMs}ms');
      expect(captureMs, lessThan(500));
      expect(await h.repo.noteCount(), 1);
    });
  });

  group('full-text search', () {
    test('prefix and accent-insensitive matching', () async {
      final id = await h.note('Caffè e cornetto al bar');
      expect((await h.repo.lexicalScores('caffe')).keys, contains(id));
      expect((await h.repo.lexicalScores('corn')).keys, contains(id));
      expect(await h.repo.lexicalScores('zzzz'), isEmpty);
    });

    test('query syntax characters cannot break the FTS query', () async {
      await h.note('plain note about cats');
      for (final q in ['cats"', 'NEAR(', '*', 'a OR', 'cat*"x', '"']) {
        await h.repo.lexicalScores(q); // must not throw
      }
    });

    test('tags and checklist items are searchable', () async {
      final id = await h.note('Shopping list:\n- olive oil\n- basil');
      expect((await h.repo.lexicalScores('basil')).keys, contains(id));
      expect((await h.repo.lexicalScores('groceries')).keys, contains(id), reason: 'AI tag "groceries" is indexed');
    });

    test('deleting removes a note from search, restoring brings it back', () async {
      final id = await h.note('secret dentist plan');
      expect((await h.repo.lexicalScores('dentist')).keys, contains(id));
      await h.repo.softDelete(id);
      expect(await h.repo.lexicalScores('dentist'), isEmpty);
      expect(await h.repo.loadNote(id), isNull);
      await h.repo.restore(id);
      expect((await h.repo.lexicalScores('dentist')).keys, contains(id));
    });
  });

  group('semantic search service', () {
    test('"groceries" finds "milk and eggs" (by meaning, not keywords)', () async {
      await h.note('milk and eggs');
      await h.note('Buy bread, pasta and tomatoes');
      await h.note('Fix the login bug in the mobile app');
      await h.note('Book flights to Lisbon for October');
      final r = await h.search.search('groceries');
      expect(r.map((e) => e.note.title).take(2), containsAll(['Milk and eggs', 'Buy bread, pasta and tomatoes']));
      expect(r.map((e) => e.note.title), isNot(contains('Fix the login bug in the mobile app')));
      expect(r.first.reasons, isNotEmpty);
    });

    test('keyword hits are returned even before the index knows the note', () async {
      final id = await h.note('quarterly offsite planning');
      h.services.brain.index.remove(id);
      final r = await h.search.search('offsite');
      expect(r.map((e) => e.note.id), contains(id));
    });

    test('related notes come with reasons', () async {
      await h.note('Book flights to Lisbon for October');
      await h.note('Hotel near Alfama in Lisbon, check-in 12 October');
      final id = await h.note('Lisbon itinerary: Belém tower, pastel de nata, tram 28');
      await h.note('Fix the login bug in the mobile app');
      final rel = await h.search.related(id);
      expect(rel.map((e) => e.note.title).join(' '), contains('Lisbon'));
      expect(rel.every((e) => e.reasons.isNotEmpty), isTrue);
    });
  });

  group('knowledge graph data', () {
    test('edges are discovered in the background and are symmetric-unique', () async {
      await h.note('Book flights to Lisbon for October');
      await h.note('Hotel near Alfama in Lisbon, check-in 12 October');
      await h.note('Lisbon itinerary: Belém tower, pastel de nata, tram 28');
      final edges = await h.services.db.select(h.services.db.edges).get();
      expect(edges, isNotEmpty);
      expect(edges.every((e) => e.a.compareTo(e.b) < 0), isTrue);
      expect(edges.map((e) => '${e.a}|${e.b}').toSet().length, edges.length);
      final g = await h.services.graph.load(minWeight: 0.3);
      expect(g.nodes, hasLength(3));
      expect(g.edges, isNotEmpty);
    });

    test('deleting a note removes its edges', () async {
      final a = await h.note('Book flights to Lisbon for October');
      await h.note('Hotel near Alfama in Lisbon, check-in 12 October');
      expect(await h.repo.edgesFor(a), isNotEmpty);
      await h.repo.softDelete(a);
      expect(await h.repo.edgesFor(a), isEmpty);
    });
  });

  group('editing & re-analysis', () {
    test('user decisions survive re-analysis; AI output is refreshed', () async {
      final id = await h.note('Remind me to call mom tomorrow');
      await h.repo.addUserTag(id, '#Family Time');
      await h.repo.setCategory(id, 'admin');
      await h.repo.setPriority(id, 3);
      final taskId = (await h.repo.loadNote(id))!.tasks.single.id;
      await h.repo.setTaskDone(taskId, true);

      await h.repo.setBody(id, 'Remind me to call mom tomorrow and buy flowers on friday');
      await h.enrichment.reanalyze(id);

      final n = (await h.repo.loadNote(id))!;
      expect(n.tags.where((t) => t.isUser).map((t) => t.name), ['family-time']);
      expect(n.categoryId, 'admin', reason: 'locked by the user');
      expect(n.priority, 3, reason: 'locked by the user');
      expect(n.tasks.map((t) => t.title), containsAll(['Call mom', 'Buy flowers']));
      expect(
        n.tasks.firstWhere((t) => t.title == 'Call mom').done,
        isTrue,
        reason: 'a completed task stays completed when its title is unchanged',
      );
      expect(n.tasks.firstWhere((t) => t.title == 'Buy flowers').done, isFalse);
    });

    test('unlocking the category returns control to the AI', () async {
      final id = await h.note('Pay the electricity bill before Friday');
      await h.repo.setCategory(id, 'admin');
      await h.repo.setCategory(id, null);
      await h.repo.setBody(id, 'Pay the electricity bill before Friday');
      await h.enrichment.reanalyze(id);
      expect((await h.repo.loadNote(id))!.categoryId, 'finance');
    });

    test('checklist edits', () async {
      final id = await h.note('Shopping list:\n- milk\n- eggs');
      var n = (await h.repo.loadNote(id))!;
      await h.repo.setChecklistChecked(n.checklist.first.id, true);
      await h.repo.addChecklistItem(id, 'Butter');
      n = (await h.repo.loadNote(id))!;
      expect(n.checklist.map((c) => (c.label, c.checked)), [('Milk', true), ('Eggs', false), ('Butter', false)]);
      await h.repo.removeChecklistItem(id, n.checklist.last.id);
      expect((await h.repo.loadNote(id))!.checklist, hasLength(2));
      // A re-analysis must not turn the list back into prose.
      await h.enrichment.reanalyze(id);
      expect((await h.repo.loadNote(id))!.kind, NoteKind.checklist);
    });

    test('completing a task cancels nothing else and can be undone', () async {
      final id = await h.note('Call the plumber tomorrow');
      final t = (await h.repo.loadNote(id))!.tasks.single;
      await h.repo.setTaskDone(t.id, true);
      expect((await h.repo.loadNote(id))!.tasks.single.done, isTrue);
      await h.repo.setTaskDone(t.id, false);
      expect((await h.repo.loadNote(id))!.tasks.single.done, isFalse);
    });
  });

  group('links', () {
    test('link previews are fetched after capture and improve title and search', () async {
      await h.dispose();
      h = await Harness.create(
        httpClient: MockClient(
          (req) async => http.Response(
            '<html><head><title>Attention Is All You Need</title>'
            '<meta property="og:description" content="The Transformer, a model architecture based on attention"/>'
            '</head></html>',
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
          ),
        ),
      );
      final id = await h.note('https://arxiv.org/abs/1706.03762');
      final n = (await h.repo.loadNote(id))!;
      expect(n.kind, NoteKind.link);
      expect(n.links.single.title, 'Attention Is All You Need');
      expect(n.title, 'Attention Is All You Need');
      final r = await h.search.search('transformer architecture');
      expect(r.map((e) => e.note.id), contains(id));
    });

    test('failed fetches are silent', () async {
      final id = await h.note('https://offline.example.com/page');
      expect((await h.repo.loadNote(id))!.links.single.title, isNull);
    });

    test('preview parser handles entities, reversed attributes and relative images', () {
      final p = LinkPreviewService.parse(
        '<title> A &amp; B </title><meta content="Desc &quot;x&quot;" name="description">'
        '<meta property="og:image" content="/img/a.png">',
        baseUri: Uri.parse('https://site.com/x/y'),
      );
      expect(p.title, 'A & B');
      expect(p.description, 'Desc "x"');
      expect(p.imageUrl, 'https://site.com/img/a.png');
    });
  });

  group('migration', () {
    test('notes embedded by another model are re-indexed', () async {
      final id = await h.note('milk and eggs');
      final payload = h.services.brain.payload(h.services.brain.brain.analyzeSync('milk and eggs'));
      await h.repo.upsertEmbedding(
        id,
        EmbeddingPayload(
          modelId: 'legacy-model',
          vector: payload.vector,
          conceptsJson: payload.conceptsJson,
          words: payload.words,
          stems: payload.stems,
          keywords: payload.keywords,
          ontologyVersion: payload.ontologyVersion,
        ),
      );
      expect(
        (await h.repo.notesNeedingReindex(h.services.brain.modelId, h.services.brain.ontologyVersion)).map((r) => r.id),
        [id],
      );
      await h.enrichment.reindexStale();
      expect(await h.repo.notesNeedingReindex(h.services.brain.modelId, h.services.brain.ontologyVersion), isEmpty);
    });

    test('index hydration restores search after a restart', () async {
      await h.note('milk and eggs');
      await h.note('Book flights to Lisbon for October');
      h.services.brain.index.clear();
      expect(await h.services.brain.hydrate(h.repo), 2);
      final r = await h.search.search('groceries');
      expect(r.first.note.title, 'Milk and eggs');
    });
  });

  group('sample data & export', () {
    test('sample corpus loads and produces tasks, categories and a connected graph', () async {
      final n = await SampleData.insert(h.capture);
      await h.capture.settle();
      expect(await h.repo.noteCount(), n);
      final summaries = await h.repo.loadSummaries();
      expect(summaries.map((s) => s.categoryId).whereType<String>().toSet().length, greaterThanOrEqualTo(8));
      expect(summaries.where((s) => s.openTasks > 0), isNotEmpty);
      final g = await h.services.graph.load(minWeight: 0.33);
      expect(g.edges.length, greaterThan(15));
      expect(g.clusters.length, greaterThanOrEqualTo(3));
    });

    test('export contains everything and is JSON-serialisable', () async {
      await h.note('Shopping list:\n- milk\n- eggs #weekly');
      final data = await h.repo.exportAll();
      final notes = data['notes']! as List<Object?>;
      expect(notes, hasLength(1));
      expect((notes.single! as Map<String, Object?>)['tags'], contains('weekly'));
      expect(await h.repo.exportMarkdown(), contains('- [ ] Milk'));
    });

    test('deleteEverything wipes all tables including the search index', () async {
      await h.note('milk and eggs');
      await h.repo.deleteEverything();
      expect(await h.repo.noteCount(), 0);
      expect(await h.repo.lexicalScores('milk'), isEmpty);
    });
  });

  group('reactive streams', () {
    test('summaries stream re-emits as notes arrive', () async {
      final emissions = <int>[];
      final sub = h.repo.watchSummaries().listen((l) => emissions.add(l.length));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await h.note('first');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await h.note('second');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await sub.cancel();
      expect(emissions.last, 2);
      expect(emissions, containsAllInOrder([0, 1, 2]));
    });

    test('category filter and pinned ordering', () async {
      await h.note('milk and eggs');
      final b = await h.note('Fix the login bug in the mobile app');
      await h.note('Book flights to Lisbon for October');
      expect((await h.repo.loadSummaries(categoryId: 'tech')).map((s) => s.id), [b]);
      await h.repo.setPinned(b, true);
      expect((await h.repo.loadSummaries()).first.id, b);
      expect((await h.repo.loadSummaries(tag: 'groceries')).map((s) => s.title), ['Milk and eggs']);
    });
  });
}
