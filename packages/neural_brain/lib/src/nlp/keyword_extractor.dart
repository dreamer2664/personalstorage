import '../text/language.dart';
import '../text/stemmer.dart';
import '../text/stopwords.dart';
import '../text/tokenizer.dart';

/// A salient word or phrase.
class Keyword {
  const Keyword(this.phrase, this.score);

  final String phrase;
  final double score;

  @override
  String toString() => '$phrase(${score.toStringAsFixed(1)})';
}

/// RAKE-style keyphrase extraction: candidate phrases are runs of content words between stop
/// words / punctuation; a word scores `degree / frequency` (words that live in long phrases and
/// repeat are salient) and a phrase is the sum of its word scores.
class KeywordExtractor {
  /// [extraGeneric] are additional words that never make good tags (the brain passes every
  /// action verb, so "fix", "clean" or "water" don't become tags).
  const KeywordExtractor({this.extraGeneric = const {}});

  final Set<String> extraGeneric;

  /// Calendar words: they describe *when*, which the date parser already captured.
  static const Set<String> _temporal = {
    'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday', 'january',
    'february', 'march', 'april', 'may', 'june', 'july', 'august', 'september', 'october',
    'november', 'december', 'morning', 'afternoon', 'evening', 'tonight', 'weekend', 'tomorrow',
    'yesterday', 'lunedi', 'martedi', 'mercoledi', 'giovedi', 'venerdi', 'sabato', 'domenica',
    'gennaio', 'febbraio', 'marzo', 'aprile', 'maggio', 'giugno', 'luglio', 'agosto', 'settembre',
    'ottobre', 'novembre', 'dicembre', 'mattina', 'pomeriggio', 'sera', 'domani', 'oggi', 'idea',
    'ideas', 'year', 'month', 'annual', 'next', 'last', 'before', 'after',
  };

  static final Set<String> _genericStems = {for (final w in _generic) Stemmer.english(w)};

  static final RegExp _clockLike = RegExp(r'^\d+(?:st|nd|rd|th|am|pm)$');

  /// Words that carry intent but no topic ("buy", "remind"): never useful as a tag.
  static const Set<String> _generic = {
    'buy', 'call', 'remind', 'reminder', 'note', 'notes', 'todo', 'need', 'get', 'make', 'take', 'go',
    'thing', 'things', 'stuff', 'new', 'good', 'great', 'nice', 'use', 'using', 'try', 'think', 'work',
    'day', 'week', 'time', 'item', 'items', 'list', 'lists', 'idea', 'reminds', 'reminded', 'app_idea', 'ricordami', 'comprare', 'compra', 'chiamare', 'nota',
    'cosa', 'cose', 'fare', 'fatto', 'send', 'check', 'also', 'etc', 'ok', 'okay', 'pm', 'am',
  };

  List<Keyword> extract(String text, {Language language = Language.unknown, int max = 6}) {
    final stop = switch (language) {
      Language.en => englishStopwords,
      Language.it => italianStopwords,
      Language.unknown => allStopwords,
    };
    final tokens = Tokenizer.tokenize(text);
    if (tokens.isEmpty) return const [];

    final phrases = <List<String>>[];
    var cur = <String>[];
    void flush() {
      if (cur.isNotEmpty) phrases.add(cur);
      cur = [];
    }

    for (var i = 0; i < tokens.length; i++) {
      final t = tokens[i];
      final uninformative = stop.contains(t.norm) ||
          t.norm.length < 2 ||
          t.isNumeric ||
          _generic.contains(t.norm) ||
          _genericStems.contains(Stemmer.english(t.norm)) ||
          _temporal.contains(t.norm) ||
          _clockLike.hasMatch(t.norm) ||
          extraGeneric.contains(t.norm);
      final punctuationBefore =
          i > 0 && RegExp(r'[.,;:!?()\n"“”]').hasMatch(text.substring(tokens[i - 1].end, t.start));
      if (uninformative || punctuationBefore) {
        flush();
        if (uninformative) continue;
      }
      cur.add(t.norm);
      if (cur.length == 2) flush();
    }
    flush();

    final freq = <String, int>{};
    final degree = <String, int>{};
    for (final p in phrases) {
      for (final w in p) {
        freq[w] = (freq[w] ?? 0) + 1;
        degree[w] = (degree[w] ?? 0) + p.length;
      }
    }
    final scored = <String, double>{};
    for (final p in phrases) {
      final s = p.fold<double>(0, (a, w) => a + degree[w]! / freq[w]!);
      final key = p.join(' ');
      scored[key] = (scored[key] ?? 0) + s;
    }
    final ranked = scored.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in ranked.take(max)) Keyword(e.key, e.value)];
  }
}
