import 'dart:io';
import 'package:neural_brain/neural_brain.dart';
import '../test/support/heldout_notes.dart';

void main() {
  final enc = StaticTextEncoder.fromBytes(File('../../assets/models/potion-base-8m.psm').readAsBytesSync());
  final brain = NeuralBrain(localEncoder: enc);
  var ok = 0;
  for (final (text, want) in heldOutNotes) {
    final a = brain.analyzeSync(text, now: DateTime(2026, 9, 30, 10));
    final good = want.split('|').contains(a.categoryId);
    if (good) ok++;
    print('${good ? '✓' : '✗'} ${a.categoryId}(${a.categoryConfidence.toStringAsFixed(2)}) want $want :: $text   tags=${a.tags.map((t) => t.name).toList()}');
  }
  print('held-out accuracy: $ok/${heldOutNotes.length} = ${(ok / heldOutNotes.length * 100).toStringAsFixed(0)}%');
}
