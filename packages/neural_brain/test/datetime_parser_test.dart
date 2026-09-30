import 'package:neural_brain/src/nlp/datetime_parser.dart';
import 'package:test/test.dart';

void main() {
  // Wednesday 30 September 2026, 10:00.
  final now = DateTime(2026, 9, 30, 10);
  const parser = DateTimeParser();

  TemporalExpression one(String text, {DateTimeParser p = parser}) {
    final r = p.parse(text, now);
    expect(r, isNotEmpty, reason: 'no temporal expression in "$text"');
    return r.first;
  }

  group('relative days and times', () {
    test('tomorrow is all-day', () {
      final e = one('tomorrow');
      expect(e.value, DateTime(2026, 10, 1));
      expect(e.hasTime, isFalse);
    });

    test('tomorrow at 5pm merges date and time, absorbing the preposition', () {
      const text = 'remind me to buy milk tomorrow at 5pm';
      final e = one(text);
      expect(e.value, DateTime(2026, 10, 1, 17));
      expect(e.hasTime, isTrue);
      expect(text.substring(e.start, e.end), 'tomorrow at 5pm');
    });

    test('tonight and day parts', () {
      expect(one('tonight').value, DateTime(2026, 9, 30, 20));
      expect(one('tomorrow morning').value, DateTime(2026, 10, 1, 9));
      expect(one('tomorrow evening at 6').value, DateTime(2026, 10, 1, 18));
    });

    test('bare hours use the meridiem heuristic', () {
      expect(one('call at 5').value, DateTime(2026, 9, 30, 17));
      // 9am already passed today => tomorrow.
      expect(one('standup at 9').value, DateTime(2026, 10, 1, 9));
      expect(one('at 17:30').value, DateTime(2026, 9, 30, 17, 30));
    });

    test('in N units', () {
      expect(one('in 2 hours').value, DateTime(2026, 9, 30, 12));
      expect(one('in 30 minutes').value, DateTime(2026, 9, 30, 10, 30));
      expect(one('in 3 days').value, DateTime(2026, 10, 3));
      expect(one('in two weeks').value, DateTime(2026, 10, 14));
      expect(one('in a month').value, DateTime(2026, 10, 30));
    });
  });

  group('weekdays', () {
    test('plain weekday is the next occurrence', () {
      expect(one('call mom on Friday').value, DateTime(2026, 10, 2));
      expect(one('Wednesday').value, DateTime(2026, 10, 7));
    });
    test('same weekday later today resolves to today', () {
      expect(one('Wednesday at 5pm').value, DateTime(2026, 9, 30, 17));
    });
    test('this / next', () {
      expect(one('this Friday').value, DateTime(2026, 10, 2));
      expect(one('next Monday').value, DateTime(2026, 10, 5));
      expect(one('next Friday').value, DateTime(2026, 10, 9));
    });
    test('abbreviations need a modifier', () {
      expect(one('on fri').value, DateTime(2026, 10, 2));
      expect(parser.parse('the sun was bright', now), isEmpty);
    });
  });

  group('explicit dates', () {
    test('numeric, day-first by default', () {
      expect(one('12/10').value, DateTime(2026, 10, 12));
      expect(one('12/10/2026').value, DateTime(2026, 10, 12));
      expect(one('25/12').value, DateTime(2026, 12, 25));
      expect(one('2026-11-03').value, DateTime(2026, 11, 3));
    });
    test('US order when requested', () {
      expect(one('10/12', p: const DateTimeParser(dayFirst: false)).value, DateTime(2026, 10, 12));
    });
    test('month names', () {
      expect(one('October 12th').value, DateTime(2026, 10, 12));
      expect(one('12 Oct').value, DateTime(2026, 10, 12));
      expect(one('the 3rd of November').value, DateTime(2026, 11, 3));
      // A date that already passed this year rolls over.
      expect(one('5 March').value, DateTime(2027, 3, 5));
    });
    test('date plus time', () {
      final e = one('dinner 5:30pm on 12/10');
      expect(e.value, DateTime(2026, 10, 12, 17, 30));
    });
    test('end of week / month / weekend', () {
      expect(one('end of the week').value, DateTime(2026, 10, 2, 17));
      expect(one('end of month').value, DateTime(2026, 9, 30, 17));
      expect(one('this weekend').value, DateTime(2026, 10, 3));
      expect(one('next week').value, DateTime(2026, 10, 5));
    });
  });

  group('deadlines', () {
    test('by / before / until mark a deadline and are absorbed', () {
      const text = 'submit report by Friday';
      final e = one(text);
      expect(e.isDeadline, isTrue);
      expect(e.value, DateTime(2026, 10, 2));
      expect(text.substring(0, e.start).trim(), 'submit report');
    });
  });

  group('italian', () {
    test('domani alle 17', () {
      expect(one('ricordami di comprare il latte domani alle 17').value, DateTime(2026, 10, 1, 17));
    });
    test('weekdays, offsets and dates', () {
      expect(one('venerdì prossimo').value, DateTime(2026, 10, 9));
      expect(one('lunedì').value, DateTime(2026, 10, 5));
      expect(one('tra 3 giorni').value, DateTime(2026, 10, 3));
      expect(one('il 15 ottobre').value, DateTime(2026, 10, 15));
      expect(one('dopodomani').value, DateTime(2026, 10, 2));
    });
    test('day parts and deadlines', () {
      expect(one('stasera').value, DateTime(2026, 9, 30, 20));
      expect(one('domani mattina').value, DateTime(2026, 10, 1, 9));
      final e = one('consegnare entro venerdì');
      expect(e.isDeadline, isTrue);
      expect(e.value, DateTime(2026, 10, 2));
    });
  });

  group('no false positives', () {
    for (final text in [
      'buy milk',
      'Buy 5 apples',
      'price is 3.50 today?'.replaceAll('today?', 'ok'),
      'I have 2 meetings',
      'May I ask a question',
      'read chapter 3',
      'we need 12 chairs',
      'call 555 1234',
    ]) {
      test('"$text"', () => expect(parser.parse(text, now), isEmpty));
    }
  });

  test('multiple expressions are returned in order', () {
    final r = parser.parse('call Bob tomorrow and pay rent on Friday', now);
    expect(r.map((e) => e.value), [DateTime(2026, 10, 1), DateTime(2026, 10, 2)]);
  });
}
