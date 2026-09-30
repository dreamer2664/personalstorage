import 'package:neural_brain/neural_brain.dart';
import 'package:test/test.dart';

void main() {
  group('DSL parser', () {
    test('parses parents, priors, markers and labels', () {
      final o = Ontology.parse('''
# comment
top@0.8 > - | Top | Cima | alpha ~weak !strong ^start ; alfa
leaf > top | Leaf node | Foglia | one two_words ; uno
''');
      expect(o.size, 2);
      expect(o['top']!.isDomain, isTrue);
      expect(o['top']!.prior, 0.8);
      expect(o['leaf']!.parents, ['top']);
      final terms = {for (final t in o['top']!.termsEn) t.phrase: t};
      expect(terms['weak']!.weight, 0.4);
      expect(terms['strong']!.weight, 1.6);
      expect(terms['start']!.anchored, isTrue);
      expect(terms['top']!.weight, 1.3, reason: 'single-word labels become terms');
      expect(o['leaf']!.termsEn.map((t) => t.phrase), contains('two words'));
      expect(
        o['leaf']!.termsEn.map((t) => t.phrase),
        isNot(contains('leaf')),
        reason: 'multi-word labels are not expanded',
      );
      expect(o['leaf']!.termsIt.map((t) => t.phrase), contains('uno'));
    });

    test('explicit weak terms beat the auto label term (book vs Books)', () {
      final o = Ontology.parse('books > - | Books | Libri | ~book novel ; libro');
      final book = o['books']!.termsEn.where((t) => t.phrase.startsWith('book'));
      expect(book.map((t) => t.phrase), ['book']);
      expect(book.single.weight, 0.4);
    });

    test('rejects malformed input', () {
      expect(() => Ontology.parse('a > - | A | A'), throwsFormatException);
      expect(() => Ontology.parse('a - | A | A | x'), throwsFormatException);
      expect(() => Ontology.parse('a > missing | A | A | x'), throwsFormatException);
      expect(() => Ontology.parse('a > - | A | A | x\na > - | A | A | y'), throwsFormatException);
    });
  });

  group('standard ontology integrity', () {
    final o = Ontology.standard;

    test('is non-trivial and acyclic', () {
      expect(o.size, greaterThan(50));
      for (final c in o.concepts) {
        expect(o.ancestors(c.id), isNot(contains(c.id)), reason: 'cycle at ${c.id}');
      }
    });

    test('every domain has children; every leaf rolls up to a domain', () {
      for (final d in o.domains) {
        expect(o.childrenOf(d.id), isNotEmpty, reason: '${d.id} has no sub-concepts');
      }
      for (final c in o.concepts.where((c) => !c.isDomain)) {
        expect(o.domainsOf(c.id), isNotEmpty, reason: c.id);
      }
    });

    test('every concept has terms and labels in both languages', () {
      for (final c in o.concepts) {
        expect(c.labelEn.trim(), isNotEmpty, reason: c.id);
        expect(c.labelIt.trim(), isNotEmpty, reason: c.id);
        expect(c.termsEn.length, greaterThanOrEqualTo(4), reason: '${c.id} EN terms');
        expect(c.termsIt.length, greaterThanOrEqualTo(3), reason: '${c.id} IT terms');
      }
    });

    test('ids are snake_case', () {
      for (final c in o.concepts) {
        expect(RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(c.id), isTrue, reason: c.id);
      }
    });
  });

  group('concept mapper', () {
    final mapper = ConceptMapper(Ontology.standard, leadVerbs: ActionExtractor.allVerbs);

    test('milk and eggs -> groceries -> shopping (hierarchy propagation)', () {
      final a = mapper.activate('milk and eggs');
      expect(a['groceries'], greaterThan(0.6));
      expect(a['shopping'], greaterThan(0.4));
      expect(a['shopping'], lessThan(a['groceries']), reason: 'parents are lifted less than the child');
    });

    test('the concept name itself activates the concept', () {
      expect(mapper.activate('groceries')['groceries'], greaterThan(0.5));
      expect(mapper.activate('travel')['travel'], greaterThan(0.4));
    });

    test('italian text maps to the same concepts', () {
      final a = mapper.activate('latte e uova', language: Language.it);
      expect(a['groceries'], greaterThan(0.6));
    });

    test('a clause-initial verb describes the action, not the topic', () {
      final a = mapper.activate('Book annual blood test and eye exam');
      expect(a['medical'], greaterThan(0.5));
      expect(a['books'], lessThan(0.25));
    });

    test('strong terms survive lead-verb damping', () {
      expect(mapper.activate('Renew passport by 15 October')['admin'], greaterThan(0.4));
    });

    test('form cues name the intended concept', () {
      expect(mapper.formCue('Idea: a thing')!.id, 'ideas');
      expect(mapper.formCue('Goal: read more')!.id, 'goals_habits');
      expect(mapper.formCue('"Stay hungry" - Jobs')!.id, 'quotes');
      expect(mapper.formCue('Watch list: Dune')!.id, 'movies_tv');
      expect(mapper.formCue('buy milk'), isNull);
    });

    test('noise and unknown text activate nothing', () {
      expect(mapper.activate('zzzz qqqq xxxx').isEmpty, isTrue);
      expect(mapper.activate('').isEmpty, isTrue);
    });

    test('sparse round trip', () {
      final a = mapper.activate('milk and eggs');
      final back = ConceptActivation.fromSparse(Ontology.standard, a.toSparse());
      expect(back['groceries'], closeTo(a['groceries'], 0.001));
      expect(back['shopping'], closeTo(a['shopping'], 0.001));
    });

    test('domain prior breaks ties towards topical domains', () {
      final o = Ontology.parse('''
a@0.5 > - | A | A | xx ; xx
b > - | B | B | xx ; xx
''');
      final act = ConceptMapper(o).activate('xx');
      expect(act.bestDomain()!.key.id, 'b');
    });
  });
}
