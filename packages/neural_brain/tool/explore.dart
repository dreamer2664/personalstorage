// ignore_for_file: avoid_print, curly_braces_in_flow_control_structures
// Developer scratchpad: prints what the brain infers for the sample corpus.
// Run: dart run tool/explore.dart
import 'dart:io';
import 'package:neural_brain/neural_brain.dart';
import 'package:neural_brain/src/sample/sample_corpus.dart';

Future<void> main(List<String> args) async {
  final enc = StaticTextEncoder.fromBytes(File('../../assets/models/potion-base-8m.psm').readAsBytesSync());
  final brain = NeuralBrain(localEncoder: enc);
  final now = DateTime(2026, 9, 30, 10);
  final index = SemanticIndex(ontology: brain.ontology, calibration: Calibration.forEncoder(enc.id));
  final analyses = <String, NoteAnalysis>{};
  for (var i = 0; i < sampleCorpus.length; i++) {
    final s = sampleCorpus[i];
    final a = brain.analyzeSync(s.text, now: now);
    analyses['n$i'] = a;
    index.upsert(IndexedNote.fromAnalysis('n$i', a, now.subtract(Duration(minutes: s.minutesAgo))));
    final ok = s.expectCategory == null ? ' ' : (s.accepts(a.categoryId) ? '✓' : '✗ want ${s.expectCategory}');
    print('n$i [${a.kind.name}/${a.language.code}] ${s.text.replaceAll('\n', ' | ')}');
    print('    cat=${a.categoryId}(${a.categoryConfidence.toStringAsFixed(2)}) $ok  tags=${a.tags}  prio=${a.priority.level.name}${a.priority.reasons}');
    if (a.actions.isNotEmpty) print('    actions=${a.actions}');
    if (a.checklist != null) print('    checklist=${a.checklist!.items}');
  }
  print('\n=== searches');
  for (final q in args.isEmpty ? ['groceries', 'shopping', 'health', 'trip', 'money', 'code', 'learning', 'doctor', 'supermarket', 'travel plans', 'ideas for a startup', 'bills', 'spesa', 'viaggio', 'cibo', 'lisbon', 'tasks'] : args) {
    final profile = await brain.profileQuery(q);
    final hits = index.search(profile, limit: 4);
    print('\nQ "$q" concepts=${profile.concepts.ranked(min: 0.3).take(3).map((e) => e.key.id).toList()}');
    for (final h in hits) {
      final id = int.parse(h.id.substring(1));
      print('   ${h.score.toStringAsFixed(2)} (n${h.semantic.toStringAsFixed(2)} c${h.concept.toStringAsFixed(2)} l${h.lexical.toStringAsFixed(2)}) ${sampleCorpus[id].text.split('\n').first}  ${h.reasons}');
    }
  }
  print('\n=== neighbours (relatedness)');
  for (final id in ['n0', 'n10', 'n13', 'n18', 'n21', 'n5']) {
    final nb = index.neighbors(id, k: 4, minRelatedness: 0.2);
    print('${sampleCorpus[int.parse(id.substring(1))].text.split('\n').first}');
    for (final n in nb) print('   ${n.score.toStringAsFixed(2)} ${sampleCorpus[int.parse(n.id.substring(1))].text.split('\n').first}  ${n.reasons}');
  }
  // distribution of pair relatedness
  final ids = analyses.keys.toList();
  final vals = <double>[];
  for (var i = 0; i < ids.length; i++) for (var j = i + 1; j < ids.length; j++) vals.add(index.relatedness(index[ids[i]]!, index[ids[j]]!));
  vals.sort();
  double p(double q) => vals[(q * (vals.length - 1)).round()];
  print('\nrelatedness over ${vals.length} pairs: median ${p(.5).toStringAsFixed(2)} p90 ${p(.9).toStringAsFixed(2)} p95 ${p(.95).toStringAsFixed(2)} p99 ${p(.99).toStringAsFixed(2)} max ${vals.last.toStringAsFixed(2)}');
}
