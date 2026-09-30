/// A contiguous piece of a note (a line, bullet or sentence) with its offsets in the source.
class Segment {
  const Segment(this.text, this.start, this.end, {this.bullet = false, this.checked});

  /// Trimmed text with any list marker removed.
  final String text;
  final int start;
  final int end;

  /// Whether the source line started with a list marker (`-`, `*`, `•`, `1.`, `[ ]`).
  final bool bullet;

  /// `true` / `false` when the line used a checkbox (`[x]` / `[ ]`), otherwise null.
  final bool? checked;

  @override
  String toString() => 'Segment("$text"@$start-$end)';
}

final RegExp _marker = RegExp(
  r'^\s*(?:(?<box>[-*•–]?\s*\[(?<state>[ xX✓✔])?\]|[☐☑✅✓✔])\s*|(?<dash>[-*•–·])\s+|(?<num>\d{1,2}[.)])\s+)',
);

/// Splits [text] into line-level segments, keeping list-marker information.
List<Segment> splitLines(String text) {
  final out = <Segment>[];
  var offset = 0;
  for (final line in text.split('\n')) {
    final lineStart = offset;
    offset += line.length + 1;
    if (line.trim().isEmpty) continue;
    final m = _marker.firstMatch(line);
    var body = line;
    var bullet = false;
    bool? checked;
    var cut = 0;
    if (m != null) {
      bullet = true;
      cut = m.end;
      body = line.substring(cut);
      if (m.namedGroup('box') != null) {
        final box = m.namedGroup('box')!;
        final state = m.namedGroup('state');
        checked = state != null && state.trim().isNotEmpty || '☑✅✓✔'.contains(box);
      }
    }
    final lead = body.length - body.trimLeft().length;
    final trimmed = body.trim();
    if (trimmed.isEmpty) continue;
    out.add(
      Segment(
        trimmed,
        lineStart + cut + lead,
        lineStart + cut + lead + trimmed.length,
        bullet: bullet,
        checked: checked,
      ),
    );
  }
  return out;
}

final RegExp _sentenceEnd = RegExp(r'(?<=[.!?;])\s+(?=[\p{Lu}\d"“(¿¡])', unicode: true);

/// Splits a segment further into sentences (keeps offsets relative to the original text).
List<Segment> splitSentences(Segment seg) {
  final parts = seg.text.split(_sentenceEnd);
  if (parts.length == 1) return [seg];
  final out = <Segment>[];
  var cursor = 0;
  for (final p in parts) {
    final idx = seg.text.indexOf(p, cursor);
    final s = seg.start + idx;
    out.add(Segment(p.trim(), s, s + p.length, bullet: seg.bullet, checked: seg.checked));
    cursor = idx + p.length;
  }
  return out;
}

/// Lines, then sentences: the granularity at which actions are extracted.
List<Segment> splitIntoClauses(String text) =>
    [for (final line in splitLines(text)) ...splitSentences(line)];
