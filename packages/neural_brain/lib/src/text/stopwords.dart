/// Compact stop-word lists (English + Italian). Words are stored accent-folded and lower-case
/// so they can be compared against `foldForMatching` output.
library;

const String _en = '''
a about above after again against all almost also am an and any are aren't as at be because been
before being below between both but by can can't cannot could couldn't did didn't do does doesn't
doing don't down during each either else even ever every few for from further get gets got had
hadn't has hasn't have haven't having he he'd he'll he's her here here's hers herself him himself
his how how's i i'd i'll i'm i've if in into is isn't it it's its itself just let's like may me
might more most much must mustn't my myself need no nor not now of off on once one only onto or
other ought our ours ourselves out over own same shall shan't she she'd she'll she's should
shouldn't so some such than that that's the their theirs them themselves then there there's these
they they'd they'll they're they've this those through to too under until up upon us very was
wasn't we we'd we'll we're we've were weren't what what's when when's where where's which while
who who's whom why why's will with won't would wouldn't yet you you'd you'll you're you've your
yours yourself yourselves s t d ll re ve m really maybe still thing things something anything
lot lots today tomorrow tonight please want wanna gonna
''';

const String _it = '''
a ad al allo alla ai agli alle anche ancora avere aveva avevano ben come con contro cui da dal
dallo dalla dai dagli dalle dei del dello della degli delle dentro di dove e ed ebbe era erano
essere faceva fare fra gli ha hai hanno ho i il in io la le lei lo loro lui ma me mi mia mie
miei mio molto nei nel nello nella negli nelle no noi non nostra nostre nostri nostro o ogni
per perche piu poi quale quali quando quanto quasi quella quelle quelli quello questa queste
questi questo se sei si sia siamo siete sono sopra sotto su sua sue sugli sui sul sullo sulla
sulle suo suoi ti tra tu tua tue tuo tuoi tutti tutto un una uno vi voi vostra vostre vostri
vostro c d l m n s t v un' dell dall nell sull all quest cosa cose qualcosa oggi domani stasera
vorrei voglio devo dovrei posso puoi poi gia sempre mai solo
''';

final Set<String> englishStopwords = _parse(_en);
final Set<String> italianStopwords = _parse(_it);

/// Union used when the language is unknown.
final Set<String> allStopwords = {...englishStopwords, ...italianStopwords};

Set<String> _parse(String raw) => raw.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toSet();
