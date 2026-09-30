import 'package:neural_brain/src/text/language.dart';
import 'package:neural_brain/src/text/segments.dart';
import 'package:neural_brain/src/text/stemmer.dart';
import 'package:neural_brain/src/text/text_utils.dart';
import 'package:neural_brain/src/text/tokenizer.dart';
import 'package:test/test.dart';

void main() {
  group('accent folding', () {
    test('stripAccents mirrors BERT (decomposable letters only)', () {
      expect(stripAccents('Café Zoë Müller'), 'cafe zoe muller');
      expect(stripAccents('Łódź ß'), 'łodz ß'); // ł and ß have no canonical decomposition
    });
    test('foldForMatching folds aggressively', () {
      expect(foldForMatching('Łódź ß Ångström'), 'lodz ss angstrom');
    });
    test('alignedFold preserves length so regex offsets stay valid', () {
      const s = 'Perché è Lunedì, Łódź — ÀÉÎ';
      expect(alignedFold(s).length, s.length);
      expect(alignedFold('Lunedì'), 'lunedi');
    });
  });

  group('tokenizer', () {
    test('keeps English contractions, splits Italian elisions', () {
      final norms = Tokenizer.tokenize("Don't forget l'uovo and John's dell'anno").map((t) => t.norm).toList();
      expect(norms, ["don't", 'forget', 'l', 'uovo', 'and', "john's", 'dell', 'anno']);
    });
    test('offsets point back into the source', () {
      const text = 'Buy 🚀 café now';
      for (final t in Tokenizer.tokenize(text)) {
        expect(text.substring(t.start, t.end), t.raw);
      }
    });
    test('content words drop stop words and numbers', () {
      expect(Tokenizer.content('Buy the 5 eggs and milk').map((t) => t.norm), ['buy', 'eggs', 'milk']);
    });
  });

  group('stemmers', () {
    test('english conflates inflections', () {
      for (final group in [
        ['groceries', 'grocery'],
        ['eggs', 'egg'],
        ['meetings', 'meeting', 'meet'],
        ['schedule', 'scheduled'],
        ['movies', 'movie'],
        ['batteries', 'battery'],
      ]) {
        expect(group.map(Stemmer.english).toSet().length, 1, reason: group.join('/'));
      }
    });
    test('italian conflates gender/number/verb forms', () {
      for (final group in [
        ['uova', 'uovo'],
        ['medico', 'medici'],
        ['comprare', 'comprato', 'compro', 'compriamo'],
        ['appuntamento', 'appuntamenti'],
      ]) {
        expect(group.map(Stemmer.italian).toSet().length, 1, reason: group.join('/'));
      }
    });
    test('short words are untouched', () {
      expect(Stemmer.english('gas'), 'gas');
      expect(Stemmer.italian('sei'), 'sei');
    });
  });

  group('language detection', () {
    const d = LanguageDetector();
    test('detects Italian and English', () {
      expect(d.detect('ricordami di comprare il latte domani'), Language.it);
      expect(d.detect('remind me to buy milk tomorrow'), Language.en);
      expect(d.detect('Appuntamento dal dentista venerdì alle 17'), Language.it);
    });
    test('unknown for ambiguous or empty input', () {
      expect(d.detect(''), Language.unknown);
      expect(d.detect('milk'), Language.unknown);
    });
  });

  group('segments', () {
    test('parses list markers and checkboxes', () {
      final s = splitLines('- [ ] buy milk\n- [x] call mom\n* eggs\n1. third\nplain');
      expect(s.map((e) => e.text), ['buy milk', 'call mom', 'eggs', 'third', 'plain']);
      expect(s.map((e) => e.bullet), [true, true, true, true, false]);
      expect(s[0].checked, false);
      expect(s[1].checked, true);
      expect(s[2].checked, isNull);
    });
    test('segment offsets map to the original text', () {
      const text = '- [ ] buy milk\nCall Bob. Then email Ann!';
      for (final s in splitIntoClauses(text)) {
        expect(text.substring(s.start, s.end).trim(), s.text);
      }
    });
    test('splits sentences but not decimals or abbreviations mid-word', () {
      expect(splitIntoClauses('Pay 3.50 now. Then rest').map((e) => e.text), ['Pay 3.50 now.', 'Then rest']);
    });
  });
}
