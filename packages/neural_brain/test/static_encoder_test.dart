import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:neural_brain/src/embeddings/static_text_encoder.dart';
import 'package:neural_brain/src/embeddings/vector_math.dart';
import 'package:test/test.dart';

/// Parity tests against the Python reference implementation (Model2Vec). The fixture file is
/// produced by `tool/build_static_model.py`, so a failure here means the Dart WordPiece /
/// pooling logic has drifted from the model the vectors were trained with.
void main() {
  final modelFile = File('../../assets/models/potion-base-8m.psm');
  final fixtureFile = File('test/fixtures/potion_reference.json');

  late StaticTextEncoder encoder;
  late List<Map<String, Object?>> cases;

  setUpAll(() {
    encoder = StaticTextEncoder.fromBytes(modelFile.readAsBytesSync());
    cases = ((jsonDecode(fixtureFile.readAsStringSync()) as Map<String, Object?>)['cases']! as List<Object?>)
        .cast<Map<String, Object?>>();
  });

  test('container metadata', () {
    expect(encoder.dim, 256);
    expect(encoder.vocabSize, 29528);
    expect(encoder.id, 'potion-base-8M-int8');
  });

  test('token ids match the reference tokenizer exactly', () {
    for (final c in cases) {
      final text = c['text']! as String;
      final expected = (c['ids']! as List<Object?>).cast<int>();
      expect(encoder.tokenIds(text), expected, reason: 'tokenization differs for "$text"');
    }
  });

  test('embeddings match the reference within int8 quantisation error', () {
    for (final c in cases) {
      final text = c['text']! as String;
      final head = (c['head']! as List<Object?>).cast<num>();
      final expectedNorm = (c['norm']! as num).toDouble();
      final v = encoder.encodeSync(text);
      expect(norm(v), closeTo(expectedNorm, 1e-3), reason: 'norm for "$text"');
      if (expectedNorm == 0) continue;
      for (var i = 0; i < head.length; i++) {
        expect(v[i], closeTo(head[i].toDouble(), 0.01), reason: 'dim $i of "$text"');
      }
    }
  });

  test('empty / unknown-only text yields the zero vector', () {
    expect(norm(encoder.encodeSync('')), 0);
    expect(norm(encoder.encodeSync('x' * 130)), 0);
  });

  test('rejects garbage containers', () {
    expect(() => StaticTextEncoder.fromBytes(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8])), throwsFormatException);
  });

  test('semantic sanity: related phrases are closer than unrelated ones', () {
    double sim(String a, String b) => cosine(encoder.encodeSync(a), encoder.encodeSync(b));
    expect(sim('dentist appointment', 'doctor visit'), greaterThan(sim('dentist appointment', 'pasta recipe')));
    expect(sim('bills', 'Pay electricity bill before Friday'), greaterThan(0.4));
    expect(sim('flights to Lisbon', 'hotel in Lisbon'), greaterThan(sim('flights to Lisbon', 'fix login bug')));
  });

  test('encoding is fast enough for typing-time hints', () {
    const text = 'Remind me to buy milk, eggs and bread tomorrow after the dentist appointment';
    final sw = Stopwatch()..start();
    for (var i = 0; i < 2000; i++) {
      encoder.encodeSync(text);
    }
    sw.stop();
    final perCallUs = sw.elapsedMicroseconds / 2000;
    // Generous bound for slow CI VMs: the real figure is typically < 100 us (JIT) / 30 us (AOT).
    expect(perCallUs, lessThan(2000));
    // ignore: avoid_print
    print('static encode: ${perCallUs.toStringAsFixed(1)} us / sentence');
  });
}
