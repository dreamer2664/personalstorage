import 'package:intl/intl.dart';

/// Human-friendly date formatting used across the app (locale aware through `intl`).
abstract final class TimeFormat {
  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Whole calendar days from [now] to [d] (negative = past).
  static int daysBetween(DateTime now, DateTime d) => _day(d).difference(_day(now)).inDays;

  /// "Today", "Tomorrow", "Yesterday", weekday within a week, else "Oct 12".
  static String relativeDay(DateTime d, DateTime now, {String? locale}) {
    final diff = daysBetween(now, d);
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    if (diff == -1) return 'Yesterday';
    if (diff > 1 && diff < 7) return DateFormat.E(locale).format(d);
    if (d.year == now.year) return DateFormat.MMMd(locale).format(d);
    return DateFormat.yMMMd(locale).format(d);
  }

  /// "Tomorrow, 5:00 PM" or just "Tomorrow" for all-day items.
  static String dueLabel(DateTime d, DateTime now, {required bool hasTime, String? locale}) {
    final day = relativeDay(d, now, locale: locale);
    return hasTime ? '$day, ${DateFormat.jm(locale).format(d)}' : day;
  }

  /// "just now", "5m", "3h", "Yesterday", "Oct 12".
  static String ago(DateTime t, DateTime now, {String? locale}) {
    final diff = now.difference(t);
    if (diff.inSeconds < 45) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24 && _day(t) == _day(now)) return '${diff.inHours}h';
    final days = daysBetween(now, t);
    if (days == -1) return 'Yesterday';
    if (days > -7) return DateFormat.E(locale).format(t);
    return t.year == now.year ? DateFormat.MMMd(locale).format(t) : DateFormat.yMMMd(locale).format(t);
  }

  /// "Wednesday, September 30".
  static String fullDate(DateTime d, {String? locale}) => DateFormat.MMMMEEEEd(locale).format(d);
}
