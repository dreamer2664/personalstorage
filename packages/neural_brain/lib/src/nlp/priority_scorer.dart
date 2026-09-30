import 'action_extractor.dart';

/// Priority levels (stored as ints: 0..3).
enum Priority {
  none(0),
  low(1),
  medium(2),
  high(3);

  const Priority(this.value);
  final int value;

  bool operator <(Priority other) => value < other.value;
  bool operator >(Priority other) => value > other.value;
  bool operator <=(Priority other) => value <= other.value;
  bool operator >=(Priority other) => value >= other.value;

  static Priority fromValue(int v) => Priority.values.firstWhere((p) => p.value == v, orElse: () => Priority.none);
}

/// Explainable priority estimate.
class PriorityAssessment {
  const PriorityAssessment(this.level, this.score, this.reasons);

  final Priority level;

  /// Raw score in `[0, 1]`.
  final double score;

  /// Human readable explanations ("due within 24h", "urgent wording").
  final List<String> reasons;

  @override
  String toString() => 'Priority(${level.name} ${score.toStringAsFixed(2)} $reasons)';
}

/// Transparent, rule-based priority model. Every signal adds to (or subtracts from) a score and
/// leaves a human-readable reason, so the UI can always answer "why is this high priority?".
class PriorityScorer {
  const PriorityScorer();

  static final RegExp _urgent = RegExp(
    r'\b(?:urgent|urgently|asap|immediately|right away|critical|emergency|urgente|subito|immediatamente|p0|p1)\b',
    caseSensitive: false,
  );
  static final RegExp _important = RegExp(
    r"\b(?:important|importante|priority|priorita|priorità|high priority|don'?t forget|do not forget|non dimenticare|must|essential|fondamentale|vital)\b",
    caseSensitive: false,
  );
  static final RegExp _deadline = RegExp(r'\b(?:deadline|due|scadenza|scade|entro|expires?|last day)\b', caseSensitive: false);
  static final RegExp _shouting = RegExp(r'!{2,}');
  static final RegExp _relaxed = RegExp(
    r'\b(?:someday|maybe|eventually|when i have time|nice to have|one day|at some point|whenever|prima o poi|magari|forse|quando ho tempo|un giorno)\b',
    caseSensitive: false,
  );

  /// [domainIds] are the ontology domains/concept ids the note activated (for small boosts).
  PriorityAssessment assess(
    String text, {
    required DateTime now,
    List<ExtractedAction> actions = const [],
    Set<String> conceptIds = const {},
  }) {
    var score = 0.0;
    final reasons = <String>[];
    void add(double v, String why) {
      score += v;
      reasons.add(why);
    }

    if (_urgent.hasMatch(text)) add(0.7, 'urgent wording');
    if (_important.hasMatch(text)) add(0.35, 'marked important');
    if (_shouting.hasMatch(text)) add(0.2, 'emphasis');
    if (_deadline.hasMatch(text) || actions.any((a) => a.isDeadline)) add(0.12, 'has a deadline');

    // Proximity of the soonest due date.
    DateTime? soonest;
    for (final a in actions) {
      final d = a.remindAt;
      if (d != null && (soonest == null || d.isBefore(soonest))) soonest = d;
    }
    if (soonest != null) {
      final hours = soonest.difference(now).inMinutes / 60.0;
      if (hours <= 2) {
        add(0.6, hours < 0 ? 'overdue' : 'due within 2 hours');
      } else if (hours <= 24) {
        add(0.42, 'due within 24 hours');
      } else if (hours <= 72) {
        add(0.3, 'due within 3 days');
      } else if (hours <= 24 * 7) {
        add(0.15, 'due this week');
      } else {
        add(0.05, 'has a due date');
      }
    } else if (actions.isNotEmpty) {
      add(0.1, 'contains a task');
    }

    if (conceptIds.contains('bills') || conceptIds.contains('taxes')) add(0.15, 'bills & taxes');
    if (conceptIds.contains('medical')) add(0.1, 'health appointment');
    if (conceptIds.contains('appointments')) add(0.05, 'appointment');

    if (_relaxed.hasMatch(text)) add(-0.35, 'relaxed wording');

    score = score.clamp(0.0, 1.0);
    final level = score >= 0.7
        ? Priority.high
        : score >= 0.4
            ? Priority.medium
            : score >= 0.15
                ? Priority.low
                : Priority.none;
    return PriorityAssessment(level, score, reasons);
  }
}
