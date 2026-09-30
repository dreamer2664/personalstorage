/// Low-level, allocation-conscious text helpers shared by every NLP component.
library;

/// Letters that have a canonical (NFD) decomposition into base letter + combining mark.
/// Dart has no built-in Unicode normalisation, so we carry the table that matters for
/// Latin-script languages (EN/IT/FR/ES/DE/PT/PL/TR...).
const Map<String, String> _decomposable = {
  'a': 'àáâãäåāăą',
  'c': 'çćĉċč',
  'd': 'ď',
  'e': 'èéêëēĕėęě',
  'g': 'ĝğġģ',
  'h': 'ĥ',
  'i': 'ìíîïĩīĭį',
  'j': 'ĵ',
  'k': 'ķ',
  'l': 'ĺļľ',
  'n': 'ñńņň',
  'o': 'òóôõöōŏő',
  'r': 'ŕŗř',
  's': 'śŝşšș',
  't': 'ţťț',
  'u': 'ùúûüũūŭůűų',
  'w': 'ŵ',
  'y': 'ýÿŷ',
  'z': 'źżž',
};

/// Extra folds that are *not* canonical decompositions (ß, æ, ø, ł ...). Only used for
/// fuzzy matching, never for WordPiece parity with BERT.
const Map<String, String> _extraFolds = {
  'ß': 'ss',
  'æ': 'ae',
  'œ': 'oe',
  'ø': 'o',
  'đ': 'd',
  'ł': 'l',
  'ħ': 'h',
  'ŧ': 't',
  'ı': 'i',
};

final Map<int, String> _stripMap = () {
  final out = <int, String>{};
  _decomposable.forEach((base, chars) {
    for (final r in chars.runes) {
      out[r] = base;
    }
  });
  return out;
}();

final Map<int, String> _foldMap = () {
  final out = <int, String>{..._stripMap};
  _extraFolds.forEach((ch, replacement) => out[ch.runes.first] = replacement);
  return out;
}();

bool _isCombiningMark(int r) => r >= 0x0300 && r <= 0x036F;

/// Lower-cases [input] and removes diacritics that BERT's `strip_accents` would remove.
String stripAccents(String input) {
  final sb = StringBuffer();
  for (final r in input.toLowerCase().runes) {
    if (_isCombiningMark(r)) continue;
    sb.write(_stripMap[r] ?? String.fromCharCode(r));
  }
  return sb.toString();
}

/// Aggressive fold used for lexical matching: lower-case, strip accents, expand ligatures.
String foldForMatching(String input) {
  final sb = StringBuffer();
  for (final r in input.toLowerCase().runes) {
    if (_isCombiningMark(r)) continue;
    sb.write(_foldMap[r] ?? String.fromCharCode(r));
  }
  return sb.toString();
}

/// Length-preserving fold: lower-cases and strips accents *one UTF-16 unit at a time*, so any
/// offset found in the result is valid in [input]. Used by regex based scanners (dates...).
String alignedFold(String input) {
  final sb = StringBuffer();
  for (final unit in input.codeUnits) {
    if (unit < 128) {
      sb.writeCharCode(unit >= 65 && unit <= 90 ? unit + 32 : unit);
      continue;
    }
    final ch = String.fromCharCode(unit);
    final lower = ch.toLowerCase();
    if (lower.length != 1) {
      sb.write(ch);
      continue;
    }
    final mapped = _foldMap[lower.codeUnitAt(0)];
    sb.write(mapped != null && mapped.length == 1 ? mapped : lower);
  }
  return sb.toString();
}

/// Whether [r] is a letter or a digit (Unicode aware for the scripts we care about).
bool isWordRune(int r) {
  if (r < 128) {
    return (r >= 48 && r <= 57) || (r >= 65 && r <= 90) || (r >= 97 && r <= 122);
  }
  if (_isCombiningMark(r)) return true;
  // Latin-1 supplement letters, Latin Extended A/B, Greek, Cyrillic, CJK, Hangul, Kana...
  if (r == 0xD7 || r == 0xF7) return false; // × ÷
  if (r >= 0xC0 && r <= 0x24F) return true;
  if (r >= 0x370 && r <= 0x52F) return true;
  if (r >= 0x1E00 && r <= 0x1FFF) return true;
  if (r >= 0x3040 && r <= 0x9FFF) return true;
  if (r >= 0xAC00 && r <= 0xD7AF) return true;
  return false;
}

bool isVowelRune(int r) {
  switch (String.fromCharCode(r)) {
    case 'a':
    case 'e':
    case 'i':
    case 'o':
    case 'u':
    case 'à':
    case 'è':
    case 'é':
    case 'ì':
    case 'ò':
    case 'ù':
      return true;
  }
  return false;
}

/// Collapses runs of whitespace into a single space and trims.
String collapseWhitespace(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

/// Title-cases the first letter only.
String capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
