import 'stopwords.dart';
import 'text_utils.dart';

/// Languages the rule-based components understand natively.
enum Language {
  en('en'),
  it('it'),
  unknown('und');

  const Language(this.code);
  final String code;
}

/// Tiny, dependency-free language identifier (EN vs IT) based on stop-word coverage plus a few
/// orthographic hints. It only needs to be right often enough to pick the right stemmer and
/// date-expression grammar; both grammars are tried anyway when the result is [Language.unknown].
class LanguageDetector {
  const LanguageDetector();

  static final RegExp _split = RegExp(r"[^\p{L}']+", unicode: true);

  Language detect(String text) {
    final words = foldForMatching(text).split(_split).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return Language.unknown;

    var en = 0.0;
    var it = 0.0;
    for (final w in words) {
      final inEn = englishStopwords.contains(w);
      final inIt = italianStopwords.contains(w);
      if (inEn && !inIt) en += 1;
      if (inIt && !inEn) it += 1;
      // Strong orthographic signals.
      if (w.endsWith("zione") || w.endsWith('zioni') || w.endsWith('mente') || w.endsWith('are')) {
        it += 0.35;
      }
      if (w.endsWith("ing") || w.endsWith("tion") || w.endsWith("ly") || w.endsWith("'s")) {
        en += 0.35;
      }
      if (_itCues.contains(w)) it += 1.5;
      if (_enCues.contains(w)) en += 1.5;
    }
    // Accented vowels that are common in Italian but rare in English.
    final accented = RegExp('[àèéìòù]').allMatches(text.toLowerCase()).length;
    it += accented * 0.5;

    if (en == 0 && it == 0) return Language.unknown;
    if (it > en * 1.15) return Language.it;
    if (en > it * 1.15) return Language.en;
    return Language.unknown;
  }

  static const Set<String> _itCues = {
    'domani',
    'oggi',
    'stasera',
    'dopodomani',
    'ricordami',
    'comprare',
    'compra',
    'devo',
    'spesa',
    'lunedi',
    'martedi',
    'mercoledi',
    'giovedi',
    'venerdi',
    'sabato',
    'domenica',
    'chiamare',
    'ciao',
    'grazie',
    'prossimo',
    'prossima',
    'settimana',
    'alle',
    'entro',
  };
  static const Set<String> _enCues = {
    'tomorrow',
    'today',
    'tonight',
    'remind',
    'buy',
    'call',
    'the',
    'and',
    'with',
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
    'next',
    'week',
    'meeting',
  };
}
