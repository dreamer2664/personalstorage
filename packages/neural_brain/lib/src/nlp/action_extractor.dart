import '../text/language.dart';
import '../text/segments.dart';
import '../text/text_utils.dart';
import 'datetime_parser.dart';

/// A to-do item recognised in free text.
class ExtractedAction {
  const ExtractedAction({
    required this.title,
    required this.start,
    required this.end,
    required this.confidence,
    required this.cue,
    this.due,
    this.hasDueTime = false,
    this.isDeadline = false,
    this.urgent = false,
  });

  /// Clean, capitalised imperative ("Buy milk"), without the cue phrase or date expression.
  final String title;

  /// Span of the source clause in the original note text.
  final int start;
  final int end;
  final double confidence;

  /// What triggered the extraction: `remind`, `need`, `todo`, `imperative`, `dated-verb`.
  final String cue;
  final DateTime? due;
  final bool hasDueTime;
  final bool isDeadline;
  final bool urgent;

  /// When a reminder should fire: the due time, or 09:00 for all-day dates.
  DateTime? get remindAt {
    final d = due;
    if (d == null) return null;
    return hasDueTime ? d : DateTime(d.year, d.month, d.day, 9);
  }

  @override
  String toString() => 'Action("$title"${due != null ? ' due $due' : ''} [$cue ${confidence.toStringAsFixed(2)}])';
}

/// Finds actionable statements ("remind me to buy X tomorrow", "call mom on Friday",
/// "ricordami di pagare l'affitto entro venerdì") and formats them as tasks with deadlines.
///
/// Precision over recall: explicit cues (`remind me`, `I need to`, `devo`, `todo:`) always count;
/// bare imperatives count when the verb is unambiguous (`buy`, `call`, `pay`...) or when a date
/// accompanies a softer verb (`read`, `plan`...).
class ActionExtractor {
  const ActionExtractor({DateTimeParser dates = const DateTimeParser()}) : _dates = dates;

  final DateTimeParser _dates;

  static final RegExp _cueEn = RegExp(
    r"^(?:(?:please|also|and|then|ok|okay|hey)\s+)*(?:"
    r"(?<remind>(?:remind|remember)\s+me\s*(?:to|about|that)?\s*|reminder\s*(?:to\s+|:)\s*|remind\s*:\s*)|"
    r"(?<forget>(?:don'?t|do\s+not|never)\s+forget\s+(?:to\s+)?|remember\s+to\s+|make\s+sure\s+(?:to\s+|i\s+|we\s+)?)|"
    r"(?<need>(?:i|we|you)\s+(?:really\s+|still\s+)?(?:need|have|want|should|must|gotta|got|ought)\s+to\s+|need\s+to\s+|have\s+to\s+|got\s+to\s+|gotta\s+|must\s+|should\s+|i'?ll\s+|i\s+will\s+|let'?s\s+)|"
    r"(?<todo>(?:to-?do|task|action(?:\s+item)?)\s*:\s*)"
    r")",
  );
  static final RegExp _cueIt = RegExp(
    r"^(?:(?:per\s+favore|anche|poi|ok)\s+)*(?:"
    r"(?<remind>ricordami\s+(?:di\s+|che\s+)?|ricordati\s+di\s+|ricorda\s+di\s+|promemoria\s*:?\s*|non\s+dimenticare\s+(?:di\s+)?|non\s+scordare\s+di\s+)|"
    r"(?<need>devo\s+|dobbiamo\s+|dovrei\s+|dovremmo\s+|bisogna\s+|ho\s+da\s+|devi\s+|da\s+fare\s*:?\s*)|"
    r"(?<todo>todo\s*:?\s*|attivita\s*:\s*)"
    r")",
  );

  static const Set<String> _strongEn = {
    'buy',
    'call',
    'email',
    'text',
    'send',
    'book',
    'schedule',
    'pay',
    'order',
    'pick',
    'renew',
    'cancel',
    'submit',
    'finish',
    'fix',
    'clean',
    'pack',
    'reply',
    'sign',
    'print',
    'return',
    'water',
    'feed',
    'confirm',
    'reserve',
    'register',
    'apply',
    'phone',
    'ring',
    'wash',
    'cook',
    'bring',
    'take',
    'get',
    'grab',
    'drop',
    'deliver',
    'collect',
    'mail',
    'transfer',
    'upload',
    'pickup',
    'message',
    'dm',
    'ping',
  };
  static const Set<String> _softEn = {
    'read',
    'learn',
    'research',
    'plan',
    'watch',
    'study',
    'check',
    'review',
    'write',
    'draft',
    'prepare',
    'organize',
    'organise',
    'update',
    'contact',
    'ask',
    'tell',
    'meet',
    'visit',
    'arrange',
    'decide',
    'test',
    'try',
    'explore',
    'look',
    'figure',
    'follow',
    'finalize',
    'complete',
    'practice',
    'install',
    'download',
    'set',
    'create',
    'make',
    'build',
    'design',
    'discuss',
    'talk',
    'revise',
    'fill',
    'start',
    'begin',
    'stop',
    'sort',
    'go',
    'do',
    'compare',
    'find',
    'choose',
  };
  static const Set<String> _strongIt = {
    'comprare',
    'compra',
    'chiamare',
    'chiama',
    'telefonare',
    'telefona',
    'inviare',
    'invia',
    'mandare',
    'manda',
    'prenotare',
    'prenota',
    'pagare',
    'paga',
    'ordinare',
    'ordina',
    'ritirare',
    'ritira',
    'rinnovare',
    'rinnova',
    'annullare',
    'annulla',
    'disdire',
    'disdici',
    'consegnare',
    'consegna',
    'finire',
    'finisci',
    'sistemare',
    'sistema',
    'pulire',
    'pulisci',
    'stampare',
    'stampa',
    'firmare',
    'firma',
    'restituire',
    'restituisci',
    'annaffiare',
    'annaffia',
    'confermare',
    'conferma',
    'richiamare',
    'richiama',
    'spedire',
    'spedisci',
    'portare',
    'porta',
    'prendere',
    'prendi',
    'lavare',
    'lava',
    'fissare',
    'fissa',
    'scrivere',
    'scrivi',
  };
  static const Set<String> _softIt = {
    'leggere',
    'leggi',
    'studiare',
    'studia',
    'cercare',
    'cerca',
    'controllare',
    'controlla',
    'rivedere',
    'rivedi',
    'preparare',
    'prepara',
    'organizzare',
    'organizza',
    'aggiornare',
    'aggiorna',
    'contattare',
    'contatta',
    'chiedere',
    'chiedi',
    'incontrare',
    'visitare',
    'decidere',
    'decidi',
    'provare',
    'prova',
    'completare',
    'completa',
    'installare',
    'installa',
    'scaricare',
    'scarica',
    'caricare',
    'carica',
    'creare',
    'crea',
    'pianificare',
    'pianifica',
    'guardare',
    'guarda',
    'imparare',
    'impara',
    'parlare',
    'parla',
    'iniziare',
    'inizia',
  };

  /// Every action verb (EN + IT, folded); lets other components tell "Book flights" (an action)
  /// from "books" (a topic).
  static final Set<String> allVerbs = {..._strongEn, ..._softEn, ..._strongIt, ..._softIt};

  static final RegExp _urgent = RegExp(
    r'\b(?:urgent|urgently|asap|immediately|critical|emergency|urgente|subito|importante|important|!{2,})|!{2,}',
    caseSensitive: false,
  );

  static final RegExp _splitter = RegExp(r"(?:\s+(?:and|then|also|e|poi|ed)\s+|\s*[;,]\s+(?:(?:and|then|e|poi)\s+)?)");

  /// Names of the capture groups a cue regex exposes (Dart throws for unknown names).
  String _cueName(RegExpMatch m) {
    for (final g in m.groupNames) {
      if (m.namedGroup(g) != null) return g == 'forget' ? 'remind' : g;
    }
    return 'need';
  }

  /// Extracts every action from [text]. [now] anchors relative dates.
  List<ExtractedAction> extract(
    String text, {
    required DateTime now,
    Language language = Language.unknown,
  }) {
    final out = <ExtractedAction>[];
    final seen = <String>{};
    for (final clause in splitIntoClauses(text)) {
      if (clause.checked == true) continue;
      for (final a in _fromClause(clause, now, language)) {
        if (seen.add(a.title.toLowerCase())) out.add(a);
      }
    }
    return out;
  }

  /// A *verbless* note that is really an event ("Dentist appointment Tuesday 4pm",
  /// "Hotel check-in 12 October") becomes a dated item titled after the event. Only call this for
  /// notes that look like events (the caller checks the concepts) and produced no other action.
  ExtractedAction? extractEvent(String text, {required DateTime now}) {
    for (final clause in splitIntoClauses(text)) {
      final exprs = _dates.parse(clause.text, now);
      if (exprs.isEmpty) continue;
      final e = exprs.first;
      final title = _cleanTitle(_cut(clause.text, 0, clause.text.length, exprs));
      if (title.length < 3 || title.split(' ').length > 9 || !RegExp(r'\p{L}', unicode: true).hasMatch(title)) continue;
      return ExtractedAction(
        title: title,
        start: clause.start,
        end: clause.end,
        confidence: 0.7,
        cue: 'event',
        due: e.value,
        hasDueTime: e.hasTime,
        isDeadline: e.isDeadline,
      );
    }
    return null;
  }

  String _firstWord(String folded) {
    final m = RegExp(r"^[a-z']+").firstMatch(folded.trimLeft());
    return m?.group(0) ?? '';
  }

  bool _isVerb(String w, Language lang) {
    if (lang != Language.it && (_strongEn.contains(w) || _softEn.contains(w))) return true;
    if (lang != Language.en && (_strongIt.contains(w) || _softIt.contains(w))) return true;
    return false;
  }

  bool _isStrong(String w, Language lang) =>
      (lang != Language.it && _strongEn.contains(w)) || (lang != Language.en && _strongIt.contains(w));

  List<ExtractedAction> _fromClause(Segment seg, DateTime now, Language lang) {
    final t = seg.text;
    final f = alignedFold(t);
    final isQuestion = t.trimRight().endsWith('?');

    // 1. Find the cue (explicit phrase) or an imperative verb.
    var bodyStart = 0;
    var cue = '';
    var confidence = 0.0;
    RegExpMatch? cm;
    if (lang != Language.it) cm = _cueEn.firstMatch(f);
    if (cm == null && lang != Language.en) cm = _cueIt.firstMatch(f);
    if (cm != null) {
      bodyStart = cm.end;
      cue = _cueName(cm);
      confidence = cue == 'remind' ? 0.95 : 0.9;
    } else {
      var pos = 0;
      final lead = RegExp(r'^(?:(?:please|per favore|also|and|then|poi)\s+)+').firstMatch(f);
      if (lead != null) pos = lead.end;
      final w = _firstWord(f.substring(pos));
      if (w.isEmpty || !_isVerb(w, lang)) return const [];
      bodyStart = pos;
      cue = 'imperative';
      confidence = _isStrong(w, lang) ? 0.75 : 0.5;
    }
    // Questions are never to-dos ('Should I call mom?'), unless phrased as an explicit reminder.
    if (isQuestion && cue != 'remind') return const [];
    if (bodyStart >= t.length) return const [];

    // 2. Temporal expressions inside the body.
    final allExprs = _dates.parse(t, now).where((e) => e.end > bodyStart).toList();
    // Attributive dates ("Sunday lunch") stay in the title and never become the due date.
    final exprs = allExprs.where((e) => !e.attributive).toList();
    if (cue == 'imperative' && exprs.isEmpty && confidence < 0.7) return const []; // soft verb, no date
    if (exprs.isNotEmpty) {
      confidence = cue == 'imperative' ? (confidence < 0.7 ? 0.6 : 0.85) : confidence;
    }

    // 3. Split "call Bob and email Ann" into separate actions.
    final starts = <int>[bodyStart];
    final boundaries = <int>[];
    for (final m in _splitter.allMatches(f)) {
      if (m.start < bodyStart) continue;
      final next = f.substring(m.end);
      if (_isVerb(_firstWord(next), lang)) {
        boundaries.add(m.start);
        starts.add(m.end);
      }
    }
    final ends = [...boundaries, t.length];
    final parts = <({int a, int b, TemporalExpression? due})>[];
    for (var i = 0; i < starts.length; i++) {
      final a = starts[i], b = ends[i];
      final own = exprs.where((e) => e.start >= a && e.start < b).firstOrNull;
      parts.add((a: a, b: b, due: own));
    }
    // A trailing date applies to earlier parts that have none ("buy milk and call mom tomorrow").
    for (var i = parts.length - 2; i >= 0; i--) {
      if (parts[i].due == null && parts[i + 1].due != null) {
        parts[i] = (a: parts[i].a, b: parts[i].b, due: parts[i + 1].due);
      }
    }

    final out = <ExtractedAction>[];
    for (final p in parts) {
      var title = _cut(t, p.a, p.b, exprs.where((e) => e.start >= p.a && e.start < p.b).toList());
      title = _cleanTitle(title);
      if (title.length < 2 || !RegExp(r'\p{L}', unicode: true).hasMatch(title)) continue;
      final d = p.due;
      out.add(
        ExtractedAction(
          title: title,
          start: seg.start,
          end: seg.end,
          confidence: confidence,
          cue: cue == 'imperative' && d != null ? 'dated-verb' : cue,
          due: d?.value,
          hasDueTime: d?.hasTime ?? false,
          isDeadline: d?.isDeadline ?? false,
          urgent: _urgent.hasMatch(t),
        ),
      );
    }
    return out;
  }

  /// `t[a..b]` with the temporal expression spans removed.
  String _cut(String t, int a, int b, List<TemporalExpression> exprs) {
    final sb = StringBuffer();
    var cursor = a;
    final sorted = [...exprs]..sort((x, y) => x.start.compareTo(y.start));
    for (final e in sorted) {
      final s = e.start < a ? a : e.start;
      if (s > cursor) sb.write(t.substring(cursor, s));
      if (e.end > cursor) cursor = e.end > b ? b : e.end;
    }
    if (cursor < b) sb.write(t.substring(cursor, b));
    return sb.toString();
  }

  String _cleanTitle(String raw) {
    var s = collapseWhitespace(raw);
    s = s.replaceAll(RegExp(r"^(?:to|that|di|che|about)\s+", caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'^[\s,;:\-–]+|[\s,;:\-–]+$'), '');
    s = s.replaceAll(RegExp(r'\s+(?:and|then|also|e|poi|ed|please|thanks|grazie)\s*$', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'[\s,;:\-–!.]+$'), '');
    s = s.replaceAll(RegExp(r'\s{2,}'), ' ');
    return capitalize(s);
  }
}
