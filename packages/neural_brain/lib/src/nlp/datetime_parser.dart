import '../text/text_utils.dart';

/// A date/time expression found in free text and resolved against a reference "now".
class TemporalExpression {
  const TemporalExpression({
    required this.start,
    required this.end,
    required this.text,
    required this.value,
    required this.hasTime,
    this.isDeadline = false,
    this.attributive = false,
  });

  /// `[start, end)` span in the original text (includes leading prepositions like "by", "on").
  final int start;
  final int end;
  final String text;

  /// Resolved local date-time. When [hasTime] is false only the calendar day is meaningful.
  final DateTime value;
  final bool hasTime;

  /// True for "by Friday", "before 5pm", "entro venerdì".
  final bool isDeadline;

  /// True when a bare weekday/date modifies a following noun ("Sunday lunch", "Monday client
  /// presentation") rather than stating when something is due. Such expressions describe an
  /// event's time; they must not become the due date of an unrelated action.
  final bool attributive;

  @override
  String toString() =>
      'Temporal("$text" -> $value${hasTime ? '' : ' (all-day)'}'
      '${isDeadline ? ' deadline' : ''})';
}

enum _Kind { date, time, daypart, instant }

enum _Part { morning, noon, afternoon, evening, tonight, night, eod }

class _Hit {
  _Hit(this.kind, this.start, this.end);

  final _Kind kind;
  final int start;
  final int end;
  DateTime? date; // midnight based
  DateTime? instant;
  int? hour;
  int? minute;
  bool? pm; // explicit meridiem
  _Part? part;
  int? weekday; // resolved lazily (needs time-of-day)
  String? weekdayMod; // next | this | null
  bool hasExplicitTime = false;
}

/// Rule-based English + Italian date/time expression parser (think "Chrono/Duckling-lite").
///
/// Supported families: relative days (today, tomorrow, domani, dopodomani), day parts (tonight,
/// this evening, stasera), weekdays with modifiers (Friday, next Monday, venerdì prossimo),
/// relative offsets (in 2 hours, in a week, tra 3 giorni), explicit dates (12/10, 12 Oct,
/// October 12th, 2026-10-12, 12 ottobre), clock times (5pm, 17:30, at 5, alle 17, noon) and
/// deadline prefixes (by, before, until, entro, prima di).
///
/// Times without a meridiem use a documented heuristic: hours 1-6 => afternoon/evening,
/// 7-11 => morning, unless a day-part word in the same phrase says otherwise.
class DateTimeParser {
  const DateTimeParser({this.dayFirst = true});

  /// Interpret `03/04` as 3 April (true, European) or March 4 (false, US).
  final bool dayFirst;

  static const Map<String, int> _months = {
    'january': 1,
    'jan': 1,
    'february': 2,
    'feb': 2,
    'march': 3,
    'mar': 3,
    'april': 4,
    'apr': 4,
    'may': 5,
    'june': 6,
    'jun': 6,
    'july': 7,
    'jul': 7,
    'august': 8,
    'aug': 8,
    'september': 9,
    'sept': 9,
    'sep': 9,
    'october': 10,
    'oct': 10,
    'november': 11,
    'nov': 11,
    'december': 12,
    'dec': 12,
    'gennaio': 1,
    'gen': 1,
    'febbraio': 2,
    'marzo': 3,
    'aprile': 4,
    'maggio': 5,
    'mag': 5,
    'giugno': 6,
    'giu': 6,
    'luglio': 7,
    'lug': 7,
    'agosto': 8,
    'settembre': 9,
    'ottobre': 10,
    'ott': 10,
    'novembre': 11,
    'dicembre': 12,
    'dic': 12,
  };

  static const Map<String, int> _weekdays = {
    'monday': 1, 'tuesday': 2, 'wednesday': 3, 'thursday': 4, 'friday': 5, 'saturday': 6,
    'sunday': 7, 'lunedi': 1, 'martedi': 2, 'mercoledi': 3, 'giovedi': 4, 'venerdi': 5,
    'sabato': 6, 'domenica': 7,
    // Abbreviations only accepted with a modifier, see _scanWeekdays.
    'mon': 1, 'tue': 2, 'tues': 2, 'wed': 3, 'thu': 4, 'thur': 4, 'thurs': 4, 'fri': 5,
    'sat': 6, 'sun': 7,
  };

  static const Map<String, int> _numbers = {
    'a': 1,
    'an': 1,
    'one': 1,
    'two': 2,
    'three': 3,
    'four': 4,
    'five': 5,
    'six': 6,
    'seven': 7,
    'eight': 8,
    'nine': 9,
    'ten': 10,
    'eleven': 11,
    'twelve': 12,
    'fifteen': 15,
    'twenty': 20,
    'thirty': 30,
    'un': 1,
    'uno': 1,
    'una': 1,
    'due': 2,
    'tre': 3,
    'quattro': 4,
    'cinque': 5,
    'sei': 6,
    'sette': 7,
    'otto': 8,
    'nove': 9,
    'dieci': 10,
    'undici': 11,
    'dodici': 12,
    'quindici': 15,
    'venti': 20,
    'trenta': 30,
  };

  static final String _monthAlt = (_months.keys.toList()..sort((a, b) => b.length - a.length)).join('|');
  static final String _numAlt = (_numbers.keys.toList()..sort((a, b) => b.length - a.length)).join('|');
  static const String _wdFull =
      'monday|tuesday|wednesday|thursday|friday|saturday|sunday|lunedi|martedi|mercoledi|giovedi|venerdi|sabato|domenica';
  static const String _wdAbbr = 'mon|tues|tue|wed|thurs|thur|thu|fri|sat|sun';

  /// Finds every temporal expression in [text], resolved relative to [now].
  List<TemporalExpression> parse(String text, DateTime now) {
    final t = alignedFold(text);
    final hits = <_Hit>[];
    bool free(int s, int e) => !hits.any((h) => s < h.end && e > h.start);
    void add(_Hit h) {
      if (free(h.start, h.end)) hits.add(h);
    }

    final today = DateTime(now.year, now.month, now.day);

    // --- relative offsets: "in 2 hours", "tra 3 giorni" -------------------------------------
    for (final m in RegExp(
      r'\b(?:in|tra|fra)\s+('
      '$_numAlt'
      r'|\d{1,3})\s*(?:(minut\w*|min|mins|hours?|hrs?|ore|ora|or[ae])|(days?|giorn[oi]|weeks?|settiman[ae]|months?|mes[ei]|years?|ann[oi]))\b',
    ).allMatches(t)) {
      final n = int.tryParse(m.group(1)!) ?? _numbers[m.group(1)!] ?? 1;
      final short = m.group(2);
      final long = m.group(3);
      final h = _Hit(short != null ? _Kind.instant : _Kind.date, m.start, m.end);
      if (short != null) {
        final isMin = short.startsWith('min');
        h.instant = now.add(isMin ? Duration(minutes: n) : Duration(hours: n));
      } else {
        final unit = long!;
        if (unit.startsWith('d') || unit.startsWith('g')) {
          h.date = today.add(Duration(days: n));
        } else if (unit.startsWith('w') || unit.startsWith('s')) {
          h.date = today.add(Duration(days: 7 * n));
        } else if (unit.startsWith('m')) {
          h.date = _addMonths(today, n);
        } else {
          h.date = DateTime(today.year + n, today.month, today.day);
        }
      }
      add(h);
    }
    for (final m in RegExp(r"\b(?:in\s+)?(?:half an hour|mezz'?ora)\b").allMatches(t)) {
      add(_Hit(_Kind.instant, m.start, m.end)..instant = now.add(const Duration(minutes: 30)));
    }
    for (final m in RegExp(
      r'\b('
      '$_numAlt'
      r'|\d{1,3})\s+(days?|weeks?|months?)\s+(?:from now|from today|later)\b',
    ).allMatches(t)) {
      final n = int.tryParse(m.group(1)!) ?? _numbers[m.group(1)!] ?? 1;
      final unit = m.group(2)!;
      final h = _Hit(_Kind.date, m.start, m.end);
      h.date = unit.startsWith('d')
          ? today.add(Duration(days: n))
          : unit.startsWith('w')
          ? today.add(Duration(days: 7 * n))
          : _addMonths(today, n);
      add(h);
    }

    // --- "next week", "end of the month", weekend ---------------------------------------------
    final monday = today.subtract(Duration(days: today.weekday - 1));
    for (final m in RegExp(
      r'\b(?:next week|la settimana prossima|prossima settimana|settimana prossima)\b',
    ).allMatches(t)) {
      add(_Hit(_Kind.date, m.start, m.end)..date = monday.add(const Duration(days: 7)));
    }
    for (final m in RegExp(r'\b(?:next month|il mese prossimo|prossimo mese|mese prossimo)\b').allMatches(t)) {
      add(_Hit(_Kind.date, m.start, m.end)..date = DateTime(today.year, today.month + 1, 1));
    }
    for (final m in RegExp(
      r'\b(?:(this|next|questo|prossimo)\s+)?(?:weekend|fine settimana|week-end)\b',
    ).allMatches(t)) {
      final next = m.group(1) == 'next' || m.group(1) == 'prossimo';
      var sat = monday.add(const Duration(days: 5));
      if (next) sat = sat.add(const Duration(days: 7));
      if (sat.isBefore(today)) sat = today;
      add(_Hit(_Kind.date, m.start, m.end)..date = sat);
    }
    for (final m in RegExp(
      r'\b(?:end of (?:the )?(week)|end of (?:the )?(month)|eow|eom|fine (?:della )?settimana lavorativa|a fine (mese)|fine (?:del )?(mese))\b',
    ).allMatches(t)) {
      final isMonth =
          m.group(2) != null || m.group(3) != null || m.group(4) != null || (m.group(0) ?? '').contains('eom');
      final d = isMonth ? DateTime(today.year, today.month + 1, 0) : monday.add(const Duration(days: 4));
      add(
        _Hit(_Kind.date, m.start, m.end)
          ..date = d.isBefore(today) ? today : d
          ..hour = 17
          ..minute = 0
          ..hasExplicitTime = true,
      );
    }

    // --- relative days ------------------------------------------------------------------------
    for (final m in RegExp(r'\b(day after tomorrow|dopodomani|tomorrow|tmrw|tmr|domani|today|oggi)\b').allMatches(t)) {
      final w = m.group(1)!;
      final offset = (w == 'day after tomorrow' || w == 'dopodomani')
          ? 2
          : (w == 'tomorrow' || w == 'tmrw' || w == 'tmr' || w == 'domani')
          ? 1
          : 0;
      add(_Hit(_Kind.date, m.start, m.end)..date = today.add(Duration(days: offset)));
    }

    // --- weekdays -----------------------------------------------------------------------------
    for (final m in RegExp(
      r'\b(?:(this|next|coming|upcoming|on|questo|prossimo)\s+)?('
      '$_wdFull'
      r')(?:\s+(prossimo|prossima|che viene))?\b',
    ).allMatches(t)) {
      final mod = m.group(1) ?? (m.group(3) != null ? 'next' : null);
      add(
        _Hit(_Kind.date, m.start, m.end)
          ..weekday = _weekdays[m.group(2)!]
          ..weekdayMod = (mod == 'next' || mod == 'prossimo' || mod == 'coming' || mod == 'upcoming')
              ? (mod == 'coming' || mod == 'upcoming' ? 'this' : 'next')
              : (mod == 'this' || mod == 'questo' ? 'this' : null),
      );
    }
    for (final m in RegExp(
      r'\b(this|next|on|by|before)\s+('
      '$_wdAbbr'
      r')\b',
    ).allMatches(t)) {
      add(
        _Hit(_Kind.date, m.start, m.end)
          ..weekday = _weekdays[m.group(2)!]
          ..weekdayMod = m.group(1) == 'next' ? 'next' : (m.group(1) == 'this' ? 'this' : null),
      );
    }

    // --- explicit dates -----------------------------------------------------------------------
    for (final m in RegExp(r'\b(\d{4})-(\d{1,2})-(\d{1,2})\b').allMatches(t)) {
      final d = _safeDate(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
      if (d != null) add(_Hit(_Kind.date, m.start, m.end)..date = d);
    }
    for (final m in RegExp(
      r'\b(\d{1,2})\s*(?:st|nd|rd|th|o|°)?\s*(?:of\s+|di\s+)?('
      '$_monthAlt'
      r')\b\.?(?:,?\s+(\d{4}))?',
    ).allMatches(t)) {
      final d = _resolveDayMonth(int.parse(m.group(1)!), _months[m.group(2)!]!, m.group(3), today);
      if (d != null) add(_Hit(_Kind.date, m.start, m.end)..date = d);
    }
    for (final m in RegExp(
      r'\b('
      '$_monthAlt'
      r')\.?\s+(\d{1,2})(?:st|nd|rd|th)?\b(?!\s*[:.]\d)(?:,?\s+(\d{4}))?',
    ).allMatches(t)) {
      final d = _resolveDayMonth(int.parse(m.group(2)!), _months[m.group(1)!]!, m.group(3), today);
      if (d != null) add(_Hit(_Kind.date, m.start, m.end)..date = d);
    }
    for (final m in RegExp(r'(?<![\d/.\-:])(\d{1,2})([/.\-])(\d{1,2})(?:\2(\d{2,4}))?(?![\d/:])').allMatches(t)) {
      final sep = m.group(2)!;
      final hasYear = m.group(4) != null;
      // "3.30" / "5-6" are far more likely times/ranges than dates: require "/" or a full date.
      if (sep != '/' && !hasYear) continue;
      var a = int.parse(m.group(1)!);
      var b = int.parse(m.group(3)!);
      if (!dayFirst) {
        final tmp = a;
        a = b;
        b = tmp;
      }
      if (a > 12 && b <= 12) {
        // unambiguous day/month regardless of the preference (e.g. 25/12)
      } else if (b > 12 && a <= 12) {
        final tmp = a;
        a = b;
        b = tmp;
      }
      final d = _resolveDayMonth(a, b, m.group(4), today);
      if (d != null) add(_Hit(_Kind.date, m.start, m.end)..date = d);
    }
    for (final m in RegExp(r'\b(?:on )?the\s+(\d{1,2})(?:st|nd|rd|th)\b').allMatches(t)) {
      final day = int.parse(m.group(1)!);
      var d = _safeDate(today.year, today.month, day);
      if (d != null && d.isBefore(today)) d = _safeDate(today.year, today.month + 1, day);
      if (d != null) add(_Hit(_Kind.date, m.start, m.end)..date = d);
    }

    // --- clock times --------------------------------------------------------------------------
    for (final m in RegExp(r'(?<![\d:.])(\d{1,2}):(\d{2})\s*(am|pm|a\.m\.|p\.m\.)?(?![\d:])').allMatches(t)) {
      final h = int.parse(m.group(1)!), mi = int.parse(m.group(2)!);
      if (h > 23 || mi > 59) continue;
      final mer = m.group(3);
      add(_timeHit(m.start, m.end, h, mi, mer));
    }
    for (final m in RegExp(r'(?<![\d:.])(\d{1,2})[.h](\d{2})\s*(am|pm|a\.m\.|p\.m\.)?(?![\d:.])').allMatches(t)) {
      final pre = t.substring((m.start - 8).clamp(0, t.length), m.start);
      final hasCue =
          RegExp(r'(?:at|alle|all|ore|@|around|verso)\s*$').hasMatch(pre) ||
          m.group(3) != null ||
          t[m.start + m.group(1)!.length] == 'h';
      if (!hasCue) continue;
      final h = int.parse(m.group(1)!), mi = int.parse(m.group(2)!);
      if (h > 23 || mi > 59) continue;
      add(_timeHit(m.start, m.end, h, mi, m.group(3)));
    }
    for (final m in RegExp(r'(?<![\d:.])(\d{1,2})\s*(am|pm|a\.m\.|p\.m\.)(?![a-z])').allMatches(t)) {
      final h = int.parse(m.group(1)!);
      if (h < 1 || h > 12) continue;
      add(_timeHit(m.start, m.end, h, 0, m.group(2)));
    }
    for (final m in RegExp(
      r"(?:\bat\b|@|\balle\b|\ball'|\bore\b|\bverso le\b|\baround\b)\s*(\d{1,2})\b(?![:.]\d)(?!\s*(?:st|nd|rd|th|%|/|-|euro|eur|usd|dollars|\$|€|people|persone|items|km|kg))",
    ).allMatches(t)) {
      final h = int.parse(m.group(1)!);
      if (h > 23) continue;
      final hit = _timeHit(m.start, m.end, h, 0, null);
      add(hit);
    }
    for (final m in RegExp(r'\b(noon|midday|mezzogiorno|midnight|mezzanotte)\b').allMatches(t)) {
      final isNoon = m.group(1) == 'noon' || m.group(1) == 'midday' || m.group(1) == 'mezzogiorno';
      add(
        _Hit(_Kind.time, m.start, m.end)
          ..hour = isNoon ? 12 : 0
          ..minute = 0
          ..hasExplicitTime = true,
      );
    }

    // --- day parts ----------------------------------------------------------------------------
    for (final m in RegExp(
      r'\b(tonight|stasera|stanotte|this (morning|afternoon|evening)|in the (morning|afternoon|evening)|(?:di )?(mattina|mattino|pomeriggio|sera|notte)|stamattina|stamani|domattina|morning|afternoon|evening|eod|end of (?:the )?day|cob|end of business)\b',
    ).allMatches(t)) {
      final w = m.group(0)!;
      _Part part;
      if (w == 'tonight' || w == 'stasera') {
        part = _Part.tonight;
      } else if (w.contains('morning') ||
          w.contains('mattina') ||
          w.contains('mattino') ||
          w == 'stamani' ||
          w == 'domattina') {
        part = _Part.morning;
      } else if (w.contains('afternoon') || w.contains('pomeriggio')) {
        part = _Part.afternoon;
      } else if (w.contains('evening') || w.contains('sera')) {
        part = _Part.evening;
      } else if (w.contains('night') || w.contains('notte')) {
        part = _Part.night;
      } else {
        part = _Part.eod;
      }
      final h = _Hit(_Kind.daypart, m.start, m.end)..part = part;
      if (w == 'domattina') {
        // "domattina" implies tomorrow as well.
        add(_Hit(_Kind.date, m.start, m.end)..date = today.add(const Duration(days: 1)));
        continue;
      }
      add(h);
    }

    return _combine(text, t, hits, now, today);
  }

  _Hit _timeHit(int s, int e, int h, int mi, String? mer) {
    final hit = _Hit(_Kind.time, s, e)
      ..hour = h
      ..minute = mi
      ..hasExplicitTime = true;
    if (mer != null) {
      final pm = mer.startsWith('p');
      hit.pm = pm;
      if (pm && h < 12) hit.hour = h + 12;
      if (!pm && h == 12) hit.hour = 0;
    }
    return hit;
  }

  /// Words that may follow a date without making it a noun modifier.
  static const Set<String> _nonNounFollowers = {
    'at',
    'alle',
    'ore',
    'and',
    'or',
    'e',
    'ed',
    'o',
    'then',
    'poi',
    'in',
    'on',
    'by',
    'before',
    'for',
    'from',
    'to',
    'until',
    'morning',
    'afternoon',
    'evening',
    'night',
    'noon',
    'mattina',
    'pomeriggio',
    'sera',
    'notte',
    'but',
    'ma',
    'so',
    'because',
    'after',
    'with',
    'con',
    'about',
    'per',
    'is',
    'around',
    'circa',
    'verso',
    'if',
    'when',
    'while',
    'since',
    'through',
    'dopo',
    'prima',
    'entro',
    'please',
    'thanks',
    'grazie',
    'too',
    'also',
    'as',
    'the',
    'a',
    'an',
    'il',
    'lo',
    'la',
    'i',
    'you',
    'we',
    'me',
    'it',
    'do',
    'don',
    'will',
    'should',
    'must',
    'can',
  };

  static const Map<_Part, int> _partHour = {
    _Part.morning: 9,
    _Part.noon: 12,
    _Part.afternoon: 15,
    _Part.evening: 18,
    _Part.tonight: 20,
    _Part.night: 21,
    _Part.eod: 17,
  };

  List<TemporalExpression> _combine(String text, String t, List<_Hit> hits, DateTime now, DateTime today) {
    hits.sort((a, b) => a.start.compareTo(b.start));
    final out = <TemporalExpression>[];
    final connector = RegExp(r"^[\s,]*(?:at|on|alle|all'|ore|@|di|of|the|around|about|verso|circa|h|in)?[\s,]*$");
    var i = 0;
    while (i < hits.length) {
      final group = <_Hit>[hits[i]];
      var j = i + 1;
      while (j < hits.length) {
        final prev = group.last;
        final next = hits[j];
        final gap = t.substring(prev.end, next.start);
        if (gap.length > 12 || !connector.hasMatch(gap)) break;
        final hasDate = group.any((h) => h.kind == _Kind.date || h.kind == _Kind.instant);
        final hasTime = group.any((h) => h.kind == _Kind.time);
        final hasPart = group.any((h) => h.kind == _Kind.daypart);
        if ((next.kind == _Kind.date || next.kind == _Kind.instant) && hasDate) break;
        if (next.kind == _Kind.time && hasTime) break;
        if (next.kind == _Kind.daypart && hasPart) break;
        group.add(next);
        j++;
      }
      i = j;
      final resolved = _resolve(group, now, today);
      if (resolved == null) continue;

      var start = group.first.start;
      final end = group.last.end;
      final after = t.substring(end);
      final atBoundary =
          after.trim().isEmpty || RegExp(r'^\s*(?:[,.;:!?)]|(?:and|then|but|e|ed|poi|ma|or|o)\b)').hasMatch(after);
      // Absorb leading prepositions and deadline markers so they don't pollute task titles.
      // Deadline words always go; plain prepositions only when the expression ends the phrase
      // ("... for Monday" -> drop "for"; "for Monday client presentation" -> keep it).
      var deadline = false;
      final prefix = RegExp(
        r'(?:^|\s)(by|before|until|till|due|entro|prima|fino|oltre|non|on|at|for|the|il|lo|la|alle|all|per|di|a|ore|@|in|from)\s*$',
      );
      const deadlineWords = {'by', 'before', 'until', 'till', 'due', 'entro', 'prima', 'fino', 'oltre'};
      String? immediatePrefix;
      for (var k = 0; k < 3; k++) {
        final m = prefix.firstMatch(t.substring(0, start));
        if (m == null) break;
        final word = m.group(1)!;
        if (k == 0) immediatePrefix = word;
        final isDeadlineWord = deadlineWords.contains(word) || word == 'non';
        if (!isDeadlineWord && !atBoundary) break;
        if (deadlineWords.contains(word)) deadline = true;
        start = m.end - m.group(0)!.length + (m.group(0)!.startsWith(RegExp(r'\s')) ? 1 : 0);
        if (word == 'in' || word == 'from') break;
      }
      // "Sunday lunch": a bare weekday/date directly followed by a noun, without a date
      // preposition in front, modifies that noun.
      final hasClock = group.any((h) => h.kind == _Kind.time || h.kind == _Kind.daypart || h.kind == _Kind.instant);
      final nextWord = RegExp(r"^\s+([a-z][a-z']*)").firstMatch(after)?.group(1);
      const datePrefixes = {
        'on',
        'by',
        'before',
        'until',
        'till',
        'for',
        'due',
        'entro',
        'per',
        'il',
        'prima',
        'fino',
        'at',
        'from',
        'since',
        'after',
        'dopo',
        'dal',
        'the',
      };
      final attributive =
          !hasClock &&
          nextWord != null &&
          !_nonNounFollowers.contains(nextWord) &&
          !(immediatePrefix != null && datePrefixes.contains(immediatePrefix) && immediatePrefix != 'the');
      out.add(
        TemporalExpression(
          start: start,
          end: end,
          text: text.substring(start, end).trim(),
          value: resolved.$1,
          hasTime: resolved.$2,
          isDeadline: deadline,
          attributive: attributive,
        ),
      );
    }
    return out;
  }

  /// Returns (value, hasTime) or null when the group can't be resolved.
  (DateTime, bool)? _resolve(List<_Hit> group, DateTime now, DateTime today) {
    final instant = group.where((h) => h.kind == _Kind.instant).firstOrNull;
    if (instant != null) return (instant.instant!, true);

    final dateHit = group.where((h) => h.kind == _Kind.date).firstOrNull;
    final timeHit = group.where((h) => h.kind == _Kind.time).firstOrNull;
    final partHit = group.where((h) => h.kind == _Kind.daypart).firstOrNull;

    int? hour = timeHit?.hour ?? dateHit?.hour;
    var minute = timeHit?.minute ?? dateHit?.minute ?? 0;
    final part = partHit?.part;

    // Meridiem inference for bare hours ("at 5", "alle 6").
    if (timeHit != null && timeHit.pm == null && hour != null && hour >= 1 && hour <= 11) {
      if (part == _Part.afternoon || part == _Part.evening || part == _Part.night || part == _Part.tonight) {
        hour += 12;
      } else if (part == _Part.morning) {
        // keep am
      } else if (hour <= 6) {
        hour += 12;
      }
    }
    if (hour == null && part != null) {
      hour = _partHour[part];
      minute = 0;
    }

    DateTime? base = dateHit?.date;
    if (dateHit != null && dateHit.weekday != null) {
      base = _resolveWeekday(dateHit, today, hour, minute, now);
    }
    if (base == null) {
      // Time-only or day-part-only expression.
      if (hour == null) return null;
      base = today;
      final candidate = DateTime(base.year, base.month, base.day, hour, minute);
      if (timeHit != null && partHit == null && candidate.isBefore(now.subtract(const Duration(minutes: 1)))) {
        base = today.add(const Duration(days: 1));
      }
    }
    if (hour == null) return (base, false);
    return (DateTime(base.year, base.month, base.day, hour, minute), true);
  }

  DateTime _resolveWeekday(_Hit hit, DateTime today, int? hour, int minute, DateTime now) {
    final target = hit.weekday!;
    final monday = today.subtract(Duration(days: today.weekday - 1));
    switch (hit.weekdayMod) {
      case 'next':
        return monday.add(Duration(days: 7 + target - 1));
      case 'this':
        var d = monday.add(Duration(days: target - 1));
        if (d.isBefore(today)) d = d.add(const Duration(days: 7));
        return d;
      default:
        var delta = (target - today.weekday) % 7;
        if (delta == 0) {
          // "meeting Friday at 5pm" said on a Friday morning means today.
          final laterToday = hour != null && DateTime(today.year, today.month, today.day, hour, minute).isAfter(now);
          delta = laterToday ? 0 : 7;
        }
        return today.add(Duration(days: delta));
    }
  }

  DateTime _addMonths(DateTime d, int n) {
    final total = d.month - 1 + n;
    final y = d.year + total ~/ 12;
    final m = total % 12 + 1;
    final last = DateTime(y, m + 1, 0).day;
    return DateTime(y, m, d.day > last ? last : d.day);
  }

  DateTime? _safeDate(int y, int m, int d) {
    final dt = DateTime(y, m, d);
    return (dt.month == ((m - 1) % 12) + 1 && dt.day == d) ? dt : null;
  }

  DateTime? _resolveDayMonth(int day, int month, String? yearRaw, DateTime today) {
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    if (yearRaw != null) {
      var y = int.parse(yearRaw);
      if (y < 100) y += 2000;
      return _safeDate(y, month, day);
    }
    var d = _safeDate(today.year, month, day);
    if (d == null) return null;
    if (d.isBefore(today)) d = _safeDate(today.year + 1, month, day);
    return d;
  }
}
