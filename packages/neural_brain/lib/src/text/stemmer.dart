import 'text_utils.dart';

/// Light, rule-based stemmers for English and Italian.
///
/// These are *not* linguistically complete (Porter/Snowball would be); they are tuned for
/// short personal notes where speed, determinism and "good enough" recall matter: the same
/// function is applied to both ontology terms and note tokens, so forms only need to agree
/// with each other (`groceries`/`grocery` -> `groceri`, `uova`/`uovo` -> `uov`).
class Stemmer {
  const Stemmer._();

  static final Map<String, String> _enCache = {};
  static final Map<String, String> _itCache = {};

  /// Stems an already folded (lower-case, accent-free) word using English rules.
  static String english(String word) => _enCache.putIfAbsent(word, () => _english(word));

  /// Stems an already folded word using Italian rules.
  static String italian(String word) => _itCache.putIfAbsent(word, () => _italian(word));

  /// Both stems, de-duplicated. Used for language-agnostic ontology lookups.
  static Set<String> both(String word) => {english(word), italian(word)};

  static bool _isVowelChar(String c) => 'aeiou'.contains(c);

  static bool _hasVowel(String s) {
    for (var i = 0; i < s.length; i++) {
      if (_isVowelChar(s[i]) || (s[i] == 'y' && i > 0)) return true;
    }
    return false;
  }

  static String _english(String w) {
    if (w.length <= 3) return w;
    if (w.endsWith("'s")) w = w.substring(0, w.length - 2);
    w = w.replaceAll("'", '');
    if (w.length <= 3) return w;

    // Plurals / third person.
    if (w.endsWith('sses')) {
      w = w.substring(0, w.length - 2);
    } else if (w.endsWith('ies') && w.length > 4) {
      w = '${w.substring(0, w.length - 3)}i';
    } else if (RegExp(r'(xes|ches|shes|zes)$').hasMatch(w)) {
      w = w.substring(0, w.length - 2);
    } else if (w.endsWith('s') && !w.endsWith('ss') && !w.endsWith('us') && !w.endsWith('is')) {
      w = w.substring(0, w.length - 1);
    }

    // -ing / -ed (only when a vowel remains in the stem).
    for (final suffix in const ['ing', 'ed']) {
      if (w.endsWith(suffix) && w.length > suffix.length + 2) {
        final stem = w.substring(0, w.length - suffix.length);
        if (_hasVowel(stem)) {
          w = _undouble(stem);
          break;
        }
      }
    }

    // A few derivational suffixes that matter for note vocabulary.
    for (final suffix in const ['ness', 'ment', 'ful', 'less', 'ly', 'er']) {
      if (w.endsWith(suffix) && w.length > suffix.length + 3) {
        w = w.substring(0, w.length - suffix.length);
        break;
      }
    }

    if (w.endsWith('y') && w.length > 3 && !_isVowelChar(w[w.length - 2])) {
      w = '${w.substring(0, w.length - 1)}i';
    }
    if (w.endsWith('e') && w.length > 4) w = w.substring(0, w.length - 1);
    return w;
  }

  static String _undouble(String s) {
    if (s.length > 2 && s[s.length - 1] == s[s.length - 2] && !'aeioulsz'.contains(s[s.length - 1])) {
      return s.substring(0, s.length - 1);
    }
    return s;
  }

  static const List<String> _itSuffixes = [
    'azioni',
    'azione',
    'zioni',
    'zione',
    'amenti',
    'amento',
    'imenti',
    'imento',
    'issimo',
    'issima',
    'issimi',
    'issime',
    'atrice',
    'atori',
    'atore',
    'mente',
    'abile',
    'ibile',
    'iamo',
    'ando',
    'endo',
    'ano',
    'ono',
    'are',
    'ere',
    'ire',
    'ato',
    'ata',
    'ati',
    'ate',
    'uto',
    'uta',
    'uti',
    'ute',
    'ito',
    'ita',
    'iti',
    'ite',
    'ete',
  ];

  static String _italian(String w) {
    if (w.length <= 3) return w;
    w = w.replaceAll("'", '');
    for (final suffix in _itSuffixes) {
      if (w.endsWith(suffix) && w.length - suffix.length >= 3) {
        w = w.substring(0, w.length - suffix.length);
        break;
      }
    }
    if (w.length > 3 && _isVowelChar(w[w.length - 1])) {
      w = w.substring(0, w.length - 1);
    }
    // Plural of -co/-go/-ca/-ga keeps the hard consonant: medic(i) == medic(o).
    return w;
  }

  /// Convenience: fold then stem with the requested language.
  static String stem(String raw, {bool italianRules = false}) {
    final folded = foldForMatching(raw);
    return italianRules ? italian(folded) : english(folded);
  }
}
