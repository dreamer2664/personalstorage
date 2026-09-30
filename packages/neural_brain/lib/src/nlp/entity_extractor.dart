import '../text/stopwords.dart';
import '../text/text_utils.dart';

/// A URL found in text, with its span so it can be stripped from titles.
class ExtractedUrl {
  const ExtractedUrl(this.url, this.start, this.end);

  /// Normalised, always includes a scheme.
  final String url;
  final int start;
  final int end;

  Uri? get uri => Uri.tryParse(url);

  /// `example.com` for `https://www.example.com/path`.
  String get host {
    final h = uri?.host ?? '';
    return h.startsWith('www.') ? h.substring(4) : h;
  }
}

/// Structured entities detected in a note.
class Entities {
  const Entities({
    this.urls = const [],
    this.emails = const [],
    this.phones = const [],
    this.hashtags = const [],
    this.mentions = const [],
    this.wikilinks = const [],
    this.money = const [],
    this.properNouns = const [],
  });

  final List<ExtractedUrl> urls;
  final List<String> emails;
  final List<String> phones;
  final List<String> hashtags;
  final List<String> mentions;

  /// `[[Note title]]` references, used to draw explicit graph edges.
  final List<String> wikilinks;
  final List<String> money;
  final List<String> properNouns;

  bool get isEmpty =>
      urls.isEmpty && emails.isEmpty && phones.isEmpty && hashtags.isEmpty && mentions.isEmpty &&
      wikilinks.isEmpty && money.isEmpty && properNouns.isEmpty;
}

/// Regex based entity extraction (no models required, runs in microseconds).
class EntityExtractor {
  /// [verbs] (folded) prevents sentence-initial imperatives ("Compare ETFs") from being read as
  /// the start of a proper-noun run.
  const EntityExtractor({this.verbs = const {}});

  final Set<String> verbs;

  static final RegExp _quoted = RegExp(r'"[^"\n]+"|“[^”\n]+”|«[^»\n]+»|(?<![\w])\x27[^\x27\n]{3,}\x27(?![\w])');

  static final RegExp _url = RegExp(
    r'''(?:(?:https?://|www\.)[^\s<>"'\]\)]+|\b[a-z0-9][a-z0-9-]*(?:\.[a-z0-9-]+)*\.(?:com|org|net|io|dev|app|it|co|edu|gov|ai|me|ly|xyz|info|eu|uk|de|fr|es|tv|gg|so|sh)\b(?:/[^\s<>"'\]\)]*)?)''',
    caseSensitive: false,
  );
  static final RegExp _email = RegExp(r'[\w.+-]+@[\w-]+(?:\.[\w-]+)+');
  static final RegExp _phone = RegExp(r'(?<![\w/.])(?:\+\d{1,3}[\s.-]?)?(?:\(?\d{2,4}\)?[\s.-]?)\d{3,4}[\s.-]?\d{3,4}(?![\w/])');
  static final RegExp _hashtag = RegExp(r'(?<![\w&#])#([\p{L}][\p{L}\d_-]{0,39})', unicode: true);
  static final RegExp _mention = RegExp(r'(?<![\w@.])@([\p{L}][\p{L}\d_.]{1,29})', unicode: true);
  static final RegExp _wiki = RegExp(r'\[\[([^\]\n]{1,80})\]\]');
  static final RegExp _money = RegExp(
    r'(?:[€$£]\s?\d[\d.,]*|\d[\d.,]*\s?(?:€|£|\$|euros|euro|eur|usd|dollars?|gbp))',
    caseSensitive: false,
  );

  static const Set<String> _notProper = {
    'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday', 'january',
    'february', 'march', 'april', 'may', 'june', 'july', 'august', 'september', 'october',
    'november', 'december', 'lunedi', 'martedi', 'mercoledi', 'giovedi', 'venerdi', 'sabato',
    'domenica', 'gennaio', 'febbraio', 'marzo', 'aprile', 'maggio', 'giugno', 'luglio', 'agosto',
    'settembre', 'ottobre', 'novembre', 'dicembre', 'idea', 'note', 'todo', 'remind', 'buy', 'call',
  };

  Entities extract(String text) {
    final urls = <ExtractedUrl>[];
    for (final m in _url.allMatches(text)) {
      var raw = m.group(0)!;
      // Trim trailing punctuation that is almost never part of the URL.
      final trimmed = raw.replaceAll(RegExp(r'[.,;:!?]+$'), '');
      final end = m.start + trimmed.length;
      raw = trimmed;
      // Skip matches that are just the domain part of an e-mail address.
      if (m.start > 0 && text[m.start - 1] == '@') continue;
      final url = raw.startsWith(RegExp(r'https?://', caseSensitive: false)) ? raw : 'https://$raw';
      urls.add(ExtractedUrl(url, m.start, end));
    }
    final emails = _email.allMatches(text).map((m) => m.group(0)!).toList();
    final phones = <String>[];
    for (final m in _phone.allMatches(text)) {
      final digits = m.group(0)!.replaceAll(RegExp(r'\D'), '');
      final hasSeparatorOrPlus = RegExp(r'[\s.\-+()]').hasMatch(m.group(0)!);
      if (digits.length >= 8 && digits.length <= 15 && hasSeparatorOrPlus && !RegExp(r'^\d{1,2}[/.\-]\d{1,2}').hasMatch(m.group(0)!)) {
        phones.add(m.group(0)!.trim());
      }
    }
    return Entities(
      urls: urls,
      emails: emails,
      phones: phones,
      hashtags: _hashtag.allMatches(text).map((m) => m.group(1)!.toLowerCase()).toSet().toList(),
      mentions: _mention.allMatches(text).map((m) => m.group(1)!).toSet().toList(),
      wikilinks: _wiki.allMatches(text).map((m) => m.group(1)!.trim()).toSet().toList(),
      money: _money.allMatches(text).map((m) => m.group(0)!.trim()).toList(),
      properNouns: _properNouns(text),
    );
  }

  /// Capitalised word runs that are not at the start of a sentence ("Lisbon", "John Smith").
  List<String> _properNouns(String text) {
    final out = <String>[];
    final quoted = _quoted.allMatches(text).toList();
    bool inQuote(int pos) => quoted.any((q) => pos > q.start && pos < q.end);
    final words = RegExp(r"[\p{L}][\p{L}'’-]*", unicode: true).allMatches(text).where((m) => !inQuote(m.start)).toList();
    var run = <String>[];
    void flush() {
      if (run.isNotEmpty) out.add(run.join(' '));
      run = [];
    }

    for (var i = 0; i < words.length; i++) {
      final m = words[i];
      final w = m.group(0)!;
      final folded = foldForMatching(w);
      final upperFirst = w[0] != w[0].toLowerCase();
      final allCaps = w.length > 1 && w == w.toUpperCase();
      final before = text.substring(0, m.start).trimRight();
      final sentenceStart = before.isEmpty || RegExp(r'[.!?:\n•\-*]$').hasMatch(before) || before.endsWith('\n');
      final ok = upperFirst &&
          !allCaps &&
          folded.length > 1 &&
          !allStopwords.contains(folded) &&
          !_notProper.contains(folded) &&
          !(sentenceStart && verbs.contains(folded));
      if (ok && !(sentenceStart && run.isEmpty && !_continuesRun(words, i, text))) {
        // adjacent only if separated by a single space
        if (run.isNotEmpty && i > 0 && text.substring(words[i - 1].end, m.start) != ' ') flush();
        run.add(w);
      } else {
        flush();
      }
    }
    flush();
    return out.toSet().toList();
  }

  /// A sentence-initial capitalised word still counts when followed by another capitalised word
  /// ("John Smith called ..."), which is a strong proper-noun signal.
  bool _continuesRun(List<RegExpMatch> words, int i, String text) {
    if (i + 1 >= words.length) return false;
    final next = words[i + 1].group(0)!;
    return next[0] != next[0].toLowerCase() &&
        next != next.toUpperCase() &&
        text.substring(words[i].end, words[i + 1].start) == ' ' &&
        !allStopwords.contains(foldForMatching(next));
  }
}
