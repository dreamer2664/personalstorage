import 'package:neural_brain/neural_brain.dart';
import 'package:test/test.dart';

void main() {
  // Wednesday 30 September 2026, 10:00.
  final now = DateTime(2026, 9, 30, 10);
  const actions = ActionExtractor();

  group('actions', () {
    test('"remind me to buy X tomorrow" becomes a task with a deadline', () {
      final r = actions.extract('Remind me to buy milk tomorrow', now: now);
      expect(r, hasLength(1));
      expect(r.single.title, 'Buy milk');
      expect(r.single.due, DateTime(2026, 10, 1));
      expect(r.single.hasDueTime, isFalse);
      expect(r.single.remindAt, DateTime(2026, 10, 1, 9), reason: 'all-day dates remind at 09:00');
      expect(r.single.cue, 'remind');
    });

    test('explicit time', () {
      final r = actions.extract('remind me to call mom tomorrow at 5pm', now: now).single;
      expect(r.title, 'Call mom');
      expect(r.due, DateTime(2026, 10, 1, 17));
      expect(r.hasDueTime, isTrue);
    });

    test('cue phrases', () {
      for (final text in [
        "Don't forget to renew the passport",
        'I need to renew the passport',
        'todo: renew the passport',
        'Have to renew the passport',
      ]) {
        expect(actions.extract(text, now: now).single.title, 'Renew the passport', reason: text);
      }
    });

    test('splits multiple actions and shares a trailing date', () {
      final r = actions.extract('Buy milk and call mom tomorrow', now: now);
      expect(r.map((a) => a.title), ['Buy milk', 'Call mom']);
      expect(r.map((a) => a.due), [DateTime(2026, 10, 1), DateTime(2026, 10, 1)]);
    });

    test('does not split noun lists', () {
      expect(actions.extract('Buy bread and milk', now: now).map((a) => a.title), ['Buy bread and milk']);
    });

    test('deadlines keep the marker out of the title', () {
      final a = actions.extract('Submit the report by Friday', now: now).single;
      expect(a.title, 'Submit the report');
      expect(a.isDeadline, isTrue);
      expect(a.due, DateTime(2026, 10, 2));
    });

    test('attributive dates stay in the title and are not deadlines', () {
      final a = actions.extract('Call mom about Sunday lunch', now: now).single;
      expect(a.title, 'Call mom about Sunday lunch');
      expect(a.due, isNull);
    });

    test('keeps prepositions inside noun phrases', () {
      final a = actions.extract('Prepare slides for Monday client presentation', now: now).single;
      expect(a.title, 'Prepare slides for client presentation');
      expect(a.due, DateTime(2026, 10, 5));
    });

    test('italian cues and infinitives', () {
      final a = actions.extract("Ricordami di pagare l'affitto entro venerdì", now: now).single;
      expect(a.title, "Pagare l'affitto");
      expect(a.due, DateTime(2026, 10, 2));
      expect(a.isDeadline, isTrue);
      expect(actions.extract('Comprare il latte domani', now: now).single.due, DateTime(2026, 10, 1));
    });

    test('precision: statements, questions and soft verbs without a date are ignored', () {
      for (final text in [
        'I called mom yesterday',
        'Milk is on sale',
        'Should I call mom?',
        'Read chapter 3', // soft verb, no date/cue
        'Meeting notes: roadmap planning',
        'The dentist was great',
      ]) {
        expect(actions.extract(text, now: now), isEmpty, reason: text);
      }
    });

    test('soft verbs count when a date is present', () {
      expect(actions.extract('Read chapter 3 by Friday', now: now), hasLength(1));
    });

    test('checked checklist lines are ignored', () {
      expect(actions.extract('- [x] call mom tomorrow', now: now), isEmpty);
    });

    test('events: verbless appointments keep their time', () {
      final e = actions.extractEvent('Dentist appointment Tuesday 4pm', now: now)!;
      expect(e.title, 'Dentist appointment');
      expect(e.due, DateTime(2026, 10, 6, 16));
    });
  });

  group('checklists', () {
    const d = ChecklistDetector();

    test('markdown and bullets', () {
      final r = d.detect('Groceries\n- [ ] milk\n- [x] eggs\n- bread')!;
      expect(r.title, 'Groceries');
      expect(r.items.map((i) => i.text), ['Milk', 'Eggs', 'Bread']);
      expect(r.items.map((i) => i.checked), [false, true, false]);
      expect(r.isConfident, isTrue);
    });

    test('cue + inline list', () {
      final r = d.detect('Shopping list: milk, eggs and bread')!;
      expect(r.items.map((i) => i.text), ['Milk', 'Eggs', 'Bread']);
      expect(r.title, 'Shopping list');
    });

    test('buy phrases need three items to be confident', () {
      expect(d.detect('Buy bread, pasta and tomatoes')!.isConfident, isTrue);
      final two = d.detect('Buy milk and eggs')!;
      expect(two.isConfident, isFalse, reason: 'two items are only suggested');
    });

    test('italian', () {
      final r = d.detect('Comprare latte, uova e pane')!;
      expect(r.items.map((i) => i.text), ['Latte', 'Uova', 'Pane']);
    });

    test('short lines without punctuation form a low-confidence list', () {
      final r = d.detect('eggs\nmilk\nbread\ncoffee')!;
      expect(r.items, hasLength(4));
      expect(r.isConfident, isFalse);
    });

    test('prose and dated tasks are not lists', () {
      expect(d.detect('Remind me to buy milk tomorrow'), isNull);
      expect(d.detect('I went to the shop. It was closed.'), isNull);
      expect(d.detect('Buy milk and eggs tomorrow at 5pm'), isNull);
      expect(d.detect('- just one bullet'), isNull);
    });

    test('suggestInline handles "milk and eggs"', () {
      final s = d.suggestInline('milk and eggs')!;
      expect(s.items.map((i) => i.text), ['Milk', 'Eggs']);
      expect(d.suggestInline('This is a long sentence about something. Really.'), isNull);
    });
  });

  group('entities', () {
    const e = EntityExtractor();

    test('urls, emails, hashtags, mentions, wikilinks, money', () {
      final r = e.extract(
        'See https://example.com/a?b=1, www.github.com/x and foo@bar.io #Idea #todo @anna [[Project X]] costs €20.50 or 15 euro',
      );
      expect(r.urls.map((u) => u.url), ['https://example.com/a?b=1', 'https://www.github.com/x']);
      expect(r.urls.first.host, 'example.com');
      expect(r.emails, ['foo@bar.io']);
      expect(r.hashtags, ['idea', 'todo']);
      expect(r.mentions, ['anna']);
      expect(r.wikilinks, ['Project X']);
      expect(r.money, containsAll(['€20.50', '15 euro']));
    });

    test('bare domains only for known TLDs; file names are not urls', () {
      expect(e.extract('open notes.txt and report.pdf').urls, isEmpty);
      expect(e.extract('try arxiv.org/abs/1706.03762').urls.single.host, 'arxiv.org');
    });

    test('proper nouns skip sentence starts and quoted titles', () {
      final r = e.extract('Lunch with John Smith in Lisbon. Then read "Thinking, Fast and Slow".');
      expect(r.properNouns, containsAll(['John Smith', 'Lisbon']));
      expect(r.properNouns, isNot(contains('Thinking')));
      expect(r.properNouns, isNot(contains('Then')));
    });
  });

  group('priority', () {
    const scorer = PriorityScorer();

    test('urgent wording and imminent deadlines are high', () {
      final urgent = actions.extract('URGENT: call the bank today', now: now);
      final p = scorer.assess('URGENT: call the bank today', now: now, actions: urgent);
      expect(p.level, Priority.high);
      expect(p.reasons, contains('urgent wording'));
    });

    test('due dates scale the score', () {
      Priority level(String text) => scorer
          .assess(
            text,
            now: now,
            actions: actions.extract(text, now: now),
          )
          .level;
      expect(level('Call mom tomorrow at 9am') > Priority.none, isTrue);
      expect(level('Call mom in 30 minutes') >= Priority.medium, isTrue);
    });

    test('relaxed wording lowers priority', () {
      final p = scorer.assess('Someday maybe learn the guitar', now: now);
      expect(p.level, Priority.none);
    });

    test('plain notes have no priority', () {
      expect(scorer.assess('Lisbon itinerary ideas', now: now).level, Priority.none);
    });
  });

  group('keywords', () {
    final k = KeywordExtractor(extraGeneric: ActionExtractor.allVerbs);

    test('ranks multi-word topics and drops generic words', () {
      final r = k.extract('Fix the vector database indexing for the notes app').map((e) => e.phrase).toList();
      expect(r, contains('vector database'));
      expect(r.join(' '), isNot(contains('fix')));
    });

    test('drops calendar and clock words', () {
      final r = k.extract('dentist appointment Tuesday morning 4pm').map((e) => e.phrase).join(' ');
      expect(r, contains('dentist'));
      expect(r, isNot(contains('tuesday')));
      expect(r, isNot(contains('4pm')));
    });
  });
}
