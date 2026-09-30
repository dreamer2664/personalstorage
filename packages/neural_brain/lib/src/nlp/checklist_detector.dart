import '../text/segments.dart';
import '../text/text_utils.dart';

/// One detected list entry.
class ChecklistItemDraft {
  const ChecklistItemDraft(this.text, {this.checked = false});

  final String text;
  final bool checked;

  @override
  String toString() => '${checked ? '[x]' : '[ ]'} $text';
}

/// A list structure found in free text.
class ChecklistDetection {
  const ChecklistDetection({
    required this.items,
    required this.confidence,
    required this.reason,
    this.title,
  });

  final String? title;
  final List<ChecklistItemDraft> items;

  /// `>= 0.75` is safe to auto-convert; lower values should only be *suggested*.
  final double confidence;
  final String reason;

  bool get isConfident => confidence >= 0.75;
}

/// Detects checklists in three ways: explicit markup (`- [ ] milk`, `* eggs`, `1. bread`),
/// a cue word followed by an inline list (`shopping list: milk, eggs and bread`), and plain
/// multi-line lists of short fragments.
class ChecklistDetector {
  const ChecklistDetector();

  static final RegExp _cue = RegExp(
    r"^\s*(?:(?:my|the|la|il|mia|nostra)\s+)?(?<label>shopping(?:\s+list)?|grocery(?:\s+list)?|groceries|to-?do(?:\s+list)?|packing(?:\s+list)?|checklist|wish\s*list|lista(?:\s+della\s+spesa)?|spesa|da\s+comprare|da\s+fare|cose\s+da\s+fare)\s*[:\-–]\s*(?<rest>.+)$",
    caseSensitive: false,
  );
  static final RegExp _buyCue = RegExp(
    r"^\s*(?:(?:i\s+need\s+to\s+|we\s+need\s+to\s+|remember\s+to\s+|don'?t\s+forget\s+to\s+)?(?:buy|get|pick\s+up|grab)|compra(?:re)?|prendere|servono|ricordati\s+di\s+comprare)\s+(?<rest>.+)$",
    caseSensitive: false,
  );
  static final RegExp _split = RegExp(r"\s*(?:,|;|\s&\s|\s\+\s|\band\b|\be\b|\bed\b)\s*", caseSensitive: false);
  static final RegExp _sentencePunct = RegExp(r'[.!?]$');

  ChecklistDetection? detect(String text) {
    final lines = splitLines(text);
    if (lines.isEmpty) return null;

    // 1. Explicit list markup.
    final bullets = lines.where((l) => l.bullet).toList();
    if (bullets.isNotEmpty && (bullets.length >= 2 || bullets.any((b) => b.checked != null))) {
      final nonBullets = lines.where((l) => !l.bullet).toList();
      if (nonBullets.length <= 1 && bullets.length >= nonBullets.length * 2) {
        final title = nonBullets.isNotEmpty && lines.first == nonBullets.first
            ? _cleanTitle(nonBullets.first.text)
            : null;
        return ChecklistDetection(
          title: title,
          items: [for (final b in bullets) ChecklistItemDraft(_cleanItem(b.text), checked: b.checked ?? false)],
          confidence: 0.95,
          reason: 'list markup',
        );
      }
    }

    // 2. Cue word + inline list on a single line ("shopping list: a, b and c").
    if (lines.length == 1) {
      final line = lines.first.text;
      final cue = _cue.firstMatch(line);
      if (cue != null) {
        final items = _splitInline(cue.namedGroup('rest')!);
        if (items.length >= 2) {
          return ChecklistDetection(
            title: _cleanTitle(cue.namedGroup('label')!),
            items: items,
            confidence: items.length >= 3 ? 0.9 : 0.8,
            reason: 'list cue "${cue.namedGroup('label')}"',
          );
        }
      }
      final buy = _buyCue.firstMatch(line);
      if (buy != null &&
          !RegExp(
            r'\b(?:tomorrow|today|tonight|domani|oggi|stasera|at|alle|by|before|entro)\b',
            caseSensitive: false,
          ).hasMatch(buy.namedGroup('rest')!)) {
        final items = _splitInline(buy.namedGroup('rest')!);
        if (items.length >= 3 || (items.length == 2 && items.every((i) => i.text.split(' ').length <= 2))) {
          return ChecklistDetection(
            items: items,
            confidence: items.length >= 3 ? 0.78 : 0.6,
            reason: 'shopping phrase',
          );
        }
      }
    }

    // 3. Several short lines without punctuation: a list of fragments.
    if (lines.length >= 3 &&
        lines.every((l) => !l.bullet && l.text.split(RegExp(r'\s+')).length <= 6 && !_sentencePunct.hasMatch(l.text))) {
      return ChecklistDetection(
        items: [for (final l in lines) ChecklistItemDraft(_cleanItem(l.text))],
        confidence: 0.7,
        reason: 'short lines',
      );
    }
    return null;
  }

  /// Low-confidence *suggestion* for a short enumeration such as "milk and eggs" or
  /// "bread, pasta, tomatoes". Only meaningful when the caller knows the note is about shopping
  /// (the brain checks the concept activation); never auto-applied.
  ChecklistDetection? suggestInline(String text) {
    final t = text.trim();
    if (t.isEmpty || t.contains('\n') || _sentencePunct.hasMatch(t) || t.split(RegExp(r'\s+')).length > 14) return null;
    final items = _splitInline(t);
    if (items.length < 2 || items.any((i) => i.text.split(' ').length > 3)) return null;
    return ChecklistDetection(items: items, confidence: 0.6, reason: 'short enumeration');
  }

  List<ChecklistItemDraft> _splitInline(String rest) {
    final parts = rest.split(_split).map((p) => p.trim().replaceAll(RegExp(r'[.!]+$'), '')).where((p) => p.isNotEmpty);
    return [for (final p in parts) ChecklistItemDraft(_cleanItem(p))];
  }

  String _cleanItem(String s) => capitalize(collapseWhitespace(s.replaceAll(RegExp(r'^[-*•–·]\s*'), '')));

  String _cleanTitle(String s) => capitalize(collapseWhitespace(s.replaceAll(RegExp(r'[:\-–]+$'), '')));
}
