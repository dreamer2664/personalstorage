import 'dart:io';

import 'package:neural_brain/neural_brain.dart';
import 'package:neural_brain/src/sample/sample_corpus.dart';
import 'package:test/test.dart';

import 'support/fresh_notes.dart';
import 'support/heldout_notes.dart';

/// End-to-end quality tests with the real bundled model. They encode the product requirements
/// (semantic search by meaning, auto-categorisation, actions -> tasks, contextual graph edges)
/// and guard against regressions when the ontology or scoring weights change.
void main() {
  final now = DateTime(2026, 9, 30, 10);
  late NeuralBrain brain;
  late SemanticIndex index;
  late List<NoteAnalysis> analyses;

  setUpAll(() {
    final encoder = StaticTextEncoder.fromBytes(File('../../assets/models/potion-base-8m.psm').readAsBytesSync());
    brain = NeuralBrain(localEncoder: encoder);
    index = SemanticIndex(ontology: brain.ontology, calibration: Calibration.forEncoder(encoder.id));
    analyses = [];
    for (var i = 0; i < sampleCorpus.length; i++) {
      final a = brain.analyzeSync(sampleCorpus[i].text, now: now);
      analyses.add(a);
      index.upsert(IndexedNote.fromAnalysis('n$i', a, now.subtract(Duration(minutes: sampleCorpus[i].minutesAgo))));
    }
  });

  String textOf(String id) => sampleCorpus[int.parse(id.substring(1))].text.split('\n').first;

  Future<List<String>> search(String q, {int limit = 5}) async {
    final profile = await brain.profileQuery(q);
    return [for (final h in index.search(profile, limit: limit)) textOf(h.id)];
  }

  group('auto-categorisation', () {
    double accuracy(Iterable<(String, bool)> results) {
      final list = results.toList();
      return list.where((r) => r.$2).length / list.length;
    }

    test('sample corpus (in-sample: the ontology was tuned on it)', () {
      final labelled = [for (var i = 0; i < sampleCorpus.length; i++) if (sampleCorpus[i].expectCategory != null) i];
      final misses = [
        for (final i in labelled)
          if (!sampleCorpus[i].accepts(analyses[i].categoryId)) '"${sampleCorpus[i].text}" -> ${analyses[i].categoryId}',
      ];
      expect(misses, isEmpty, reason: misses.join('\n'));
    });

    test('held-out v1 (tuned once after first evaluation)', () {
      final r = [for (final (text, want) in heldOutNotes) (text, want.split('|').contains(brain.analyzeSync(text, now: now).categoryId))];
      expect(accuracy(r), greaterThanOrEqualTo(0.9), reason: r.where((e) => !e.$2).map((e) => e.$1).join('\n'));
    });

    test('held-out v2 (first unseen evaluation was 82%; now tuned-on, guards regressions)', () {
      final r = [for (final (text, want) in freshNotes) (text, want.split('|').contains(brain.analyzeSync(text, now: now).categoryId))];
      expect(accuracy(r), greaterThanOrEqualTo(0.9), reason: r.where((e) => !e.$2).map((e) => e.$1).join('\n'));
    });

    test('unrecognisable text stays uncategorised rather than mislabelled', () {
      expect(brain.analyzeSync('zzz qqq xxx www', now: now).categoryId, isNull);
    });

    test('an explicit form overrides topical evidence', () {
      expect(brain.analyzeSync('Idea per una app di ricette con gli ingredienti del frigo', now: now).categoryId, 'ideas');
    });
  });

  group('tags', () {
    test('"milk and eggs" is tagged groceries without any manual input', () {
      final a = brain.analyzeSync('milk and eggs', now: now);
      expect(a.tags.map((t) => t.name), contains('groceries'));
      expect(a.categoryId, 'shopping');
    });

    test('user hashtags are preserved and ranked first', () {
      final a = brain.analyzeSync('Fix onboarding copy #Launch #ux', now: now);
      expect(a.tags.take(2).map((t) => t.name), containsAll(['launch', 'ux']));
      expect(a.tags.first.source, TagSource.user);
    });

    test('tags are lower-case, short and de-duplicated', () {
      for (final a in analyses) {
        expect(a.tags.length, lessThanOrEqualTo(6));
        expect(a.tags.map((t) => t.name).toSet().length, a.tags.length);
        for (final t in a.tags) {
          expect(t.name, t.name.toLowerCase());
        }
      }
    });

    test('italian notes get italian concept tags', () {
      final a = brain.analyzeSync('Comprare latte, uova e pane', now: now);
      expect(a.tags.map((t) => t.name), contains('spesa'));
    });
  });

  group('structure', () {
    test('kinds', () {
      expect(brain.analyzeSync('Buy bread, pasta and tomatoes', now: now).kind, NoteKind.checklist);
      expect(brain.analyzeSync('https://example.com/some/article', now: now).kind, NoteKind.link);
      expect(brain.analyzeSync('see https://example.com it is great and long', now: now).kind, NoteKind.text);
      expect(brain.analyzeSync('holiday', now: now, imageCount: 3).kind, NoteKind.image);
      expect(brain.analyzeSync('milk and eggs', now: now).kind, NoteKind.text);
    });

    test('"milk and eggs" offers a checklist suggestion but does not force one', () {
      final a = brain.analyzeSync('milk and eggs', now: now);
      expect(a.checklist, isNull);
      expect(a.checklistSuggestion!.items.map((i) => i.text), ['Milk', 'Eggs']);
    });

    test('titles', () {
      expect(brain.analyzeSync('Shopping list:\n- milk\n- eggs', now: now).title, 'Shopping list');
      expect(brain.analyzeSync('https://arxiv.org/abs/1706.03762', now: now).title, 'arxiv.org');
      final long = brain.analyzeSync('${'word ' * 40}end', now: now).title;
      expect(long.length, lessThanOrEqualTo(73));
      expect(long, endsWith('…'));
    });

    test('checklist notes do not spawn tasks', () {
      expect(brain.analyzeSync('Shopping list:\n- call mom\n- pay rent', now: now).actions, isEmpty);
    });

    test('empty input is safe', () {
      final a = brain.analyzeSync('   ', now: now);
      expect(a.title, 'Untitled');
      expect(a.actions, isEmpty);
      expect(a.categoryId, isNull);
    });
  });

  group('actions and priority', () {
    test('"remind me to buy X tomorrow" -> task with deadline', () {
      final a = brain.analyzeSync('Remind me to buy oat milk tomorrow at 8am', now: now);
      expect(a.actions, hasLength(1));
      expect(a.actions.single.title, 'Buy oat milk');
      expect(a.actions.single.due, DateTime(2026, 10, 2 - 1, 8));
    });

    test('appointments without a verb become dated events', () {
      final a = brain.analyzeSync('Dentist appointment Tuesday 4pm', now: now);
      expect(a.actions.single.cue, 'event');
      expect(a.actions.single.due, DateTime(2026, 10, 6, 16));
    });

    test('priority follows urgency and proximity', () {
      final urgent = brain.analyzeSync('URGENT pay the electricity bill today', now: now).priority;
      final relaxed = brain.analyzeSync('Someday learn to play the piano', now: now).priority;
      expect(urgent.level, Priority.high);
      expect(relaxed.level, Priority.none);
    });
  });

  group('semantic search (by meaning, not keywords)', () {
    test('"groceries" finds "milk and eggs" (the headline example)', () async {
      final r = await search('groceries', limit: 4);
      expect(r, contains('milk and eggs'));
      expect(r.take(3), contains('milk and eggs'));
    });

    test('every top result for "groceries" is food-related', () async {
      final r = await search('groceries', limit: 4);
      for (final t in r) {
        expect(t.toLowerCase(), anyOf(contains('milk'), contains('bread'), contains('shopping'), contains('latte'), contains('ricette')));
      }
    });

    final expectations = <String, (String, int)>{
      'supermarket': ('milk and eggs', 3),
      'doctor': ('Dentist appointment Tuesday 4pm', 1),
      'bills': ('Pay the electricity bill before Friday', 1),
      'money': ('Pay the electricity bill before Friday', 3),
      'startup': ('Startup idea: marketplace for local repair shops', 1),
      'trip': ('Book flights to Lisbon for October', 3),
      'code': ('Fix the login bug in the mobile app', 1),
      'lisbon': ('Hotel near Alfama in Lisbon, check-in 12 October', 4),
      'health': ('Dentist appointment Tuesday 4pm', 2),
    };
    expectations.forEach((query, want) {
      test('"$query" ranks "${want.$1}" in the top ${want.$2}', () async {
        final r = await search(query, limit: want.$2);
        expect(r, contains(want.$1), reason: 'got $r');
      });
    });

    test('cross-language: Italian queries find English notes and vice versa', () async {
      expect(await search('spesa', limit: 4), contains('milk and eggs'));
      expect(await search('viaggio', limit: 5), anyOf(contains('Book flights to Lisbon for October'), contains('Hotel near Alfama in Lisbon, check-in 12 October')));
      expect(await search('latte', limit: 5), contains('Comprare latte, uova e pane'));
    });

    test('exact keywords outrank semantic neighbours', () async {
      expect((await search('passport', limit: 1)).single, anyOf(contains('passport')));
    });

    test('gibberish returns nothing', () async {
      expect(await search('qzxv wkjh', limit: 5), isEmpty);
    });

    test('hashtag queries filter by tag', () async {
      final a = brain.analyzeSync('Plan offsite #q4 #offsite', now: now);
      index.upsert(IndexedNote.fromAnalysis('tagged', a, now));
      final hits = index.search(await brain.profileQuery('#q4'), limit: 3);
      expect(hits.first.id, 'tagged');
      index.remove('tagged');
    });

    test('search explains its results', () async {
      final hits = index.search(await brain.profileQuery('groceries'), limit: 1);
      expect(hits.single.reasons, isNotEmpty);
      expect(hits.single.reasons.join(' '), contains('Groceries'));
    });
  });

  group('knowledge graph edges', () {
    test('related notes are discovered and explained', () {
      final id = 'n${sampleCorpus.indexWhere((s) => s.text.startsWith('Book flights'))}';
      final nb = index.neighbors(id, k: 4, minRelatedness: 0.33);
      final texts = nb.map((n) => textOf(n.id)).join(' | ');
      expect(texts, contains('Lisbon'));
      expect(nb.every((n) => n.reasons.isNotEmpty), isTrue);
    });

    test('unrelated notes are not connected', () {
      final a = index['n${sampleCorpus.indexWhere((s) => s.text.startsWith('milk and eggs'))}']!;
      final b = index['n${sampleCorpus.indexWhere((s) => s.text.startsWith('Fix the login bug'))}']!;
      expect(index.relatedness(a, b), lessThan(0.2));
    });

    test('clusters emerge from the corpus: Lisbon trip notes and groceries group together', () {
      final notes = <GraphNoteInput>[];
      final edges = <GraphEdgeInput>[];
      for (var i = 0; i < sampleCorpus.length; i++) {
        final a = analyses[i];
        notes.add(GraphNoteInput(id: 'n$i', label: a.title, categoryId: a.categoryId, tags: [for (final t in a.tags) t.name]));
        for (final nb in index.neighbors('n$i', k: 4, minRelatedness: 0.33)) {
          edges.add(GraphEdgeInput('n$i', nb.id, nb.score, reason: nb.reasons.first));
        }
      }
      final g = GraphBuilder.build(notes: notes, edges: edges);
      int cluster(String prefix) => g.nodes[g.indexOf['n${sampleCorpus.indexWhere((s) => s.text.startsWith(prefix))}']!].cluster;
      expect(cluster('Book flights'), greaterThanOrEqualTo(0));
      expect(cluster('Book flights'), cluster('Hotel near Alfama'));
      expect(cluster('Book flights'), cluster('Lisbon itinerary'));
      expect(cluster('milk and eggs'), cluster('Buy bread'));
      expect(cluster('milk and eggs'), isNot(cluster('Book flights')));
      expect(g.edges.length, inInclusiveRange(20, 200));
    });
  });

  group('performance', () {
    test('analysis of a typical note takes well under a frame', () {
      const text = 'Remind me to buy milk, eggs and bread tomorrow at 5pm after the dentist appointment, and call mom about Sunday lunch';
      brain.analyzeSync(text, now: now); // warm-up
      final sw = Stopwatch()..start();
      for (var i = 0; i < 300; i++) {
        brain.analyzeSync(text, now: now);
      }
      final ms = sw.elapsedMicroseconds / 300 / 1000;
      // ignore: avoid_print
      print('analyzeSync: ${ms.toStringAsFixed(2)} ms / note');
      expect(ms, lessThan(16));
    });

    test('search stays interactive with thousands of notes', () async {
      final big = SemanticIndex(ontology: brain.ontology, calibration: index.calibration);
      for (var i = 0; i < 5000; i++) {
        final base = analyses[i % analyses.length];
        big.upsert(IndexedNote.fromAnalysis('x$i', base, now));
      }
      final profile = await brain.profileQuery('groceries');
      big.search(profile); // warm-up
      final sw = Stopwatch()..start();
      for (var i = 0; i < 10; i++) {
        big.search(profile, limit: 30);
      }
      final ms = sw.elapsedMilliseconds / 10;
      // ignore: avoid_print
      print('search over 5000 notes: ${ms.toStringAsFixed(1)} ms');
      expect(ms, lessThan(150));
    });
  });
}
