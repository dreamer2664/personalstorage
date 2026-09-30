import 'language.dart';
import 'stemmer.dart';
import 'stopwords.dart';
import 'text_utils.dart';

/// A word-level token with its position in the source string.
class Token {
  const Token(this.raw, this.norm, this.start, this.end);

  /// Text exactly as written.
  final String raw;

  /// Lower-case, accent-folded form.
  final String norm;

  /// Offsets into the original string: `[start, end)`.
  final int start;
  final int end;

  bool get isNumeric => norm.isNotEmpty && norm.codeUnits.every((c) => c >= 48 && c <= 57);

  @override
  String toString() => 'Token($raw@$start)';
}

/// Unicode-aware word tokenizer. Apostrophes inside English contractions (`don't`, `John's`)
/// are kept, while Italian elisions (`l'uovo`, `dell'anno`) are split.
class Tokenizer {
  const Tokenizer._();

  static List<Token> tokenize(String text) {
    final tokens = <Token>[];
    final runes = text.runes.toList(growable: false);
    // Rune index -> UTF-16 offset, so that offsets stay valid for astral characters.
    final offsets = List<int>.filled(runes.length + 1, 0);
    var acc = 0;
    for (var i = 0; i < runes.length; i++) {
      offsets[i] = acc;
      acc += runes[i] > 0xFFFF ? 2 : 1;
    }
    offsets[runes.length] = acc;

    var i = 0;
    while (i < runes.length) {
      if (!isWordRune(runes[i])) {
        i++;
        continue;
      }
      final startRune = i;
      var j = i;
      while (j < runes.length) {
        final r = runes[j];
        if (isWordRune(r)) {
          j++;
          continue;
        }
        final isApostrophe = r == 0x27 || r == 0x2019;
        if (isApostrophe && j + 1 < runes.length && isWordRune(runes[j + 1]) && j > startRune) {
          // Elision (l'uovo) when the next letter is a vowel/h: split. Contraction: keep.
          final next = String.fromCharCode(runes[j + 1]).toLowerCase();
          final elision = isVowelRune(next.runes.first) || next == 'h';
          if (!elision) {
            j++;
            continue;
          }
        }
        break;
      }
      final raw = text.substring(offsets[startRune], offsets[j]);
      final norm = foldForMatching(raw).replaceAll('\u2019', "'");
      tokens.add(Token(raw, norm, offsets[startRune], offsets[j]));
      i = j; // runes[j] is a separator (or the end), skipped on the next iteration.
    }
    return tokens;
  }

  /// Content words only (no stop-words, no bare numbers, length >= 2).
  static List<Token> content(String text, {Language language = Language.unknown}) {
    final stop = switch (language) {
      Language.en => englishStopwords,
      Language.it => italianStopwords,
      Language.unknown => allStopwords,
    };
    return tokenize(
      text,
    ).where((t) => t.norm.length >= 2 && !t.isNumeric && !stop.contains(t.norm)).toList(growable: false);
  }

  /// Distinct stems (both EN and IT variants) of the content words.
  static Set<String> stems(String text, {Language language = Language.unknown}) {
    final out = <String>{};
    for (final t in content(text, language: language)) {
      switch (language) {
        case Language.en:
          out.add(Stemmer.english(t.norm));
        case Language.it:
          out.add(Stemmer.italian(t.norm));
        case Language.unknown:
          out.addAll(Stemmer.both(t.norm));
      }
    }
    return out;
  }
}
