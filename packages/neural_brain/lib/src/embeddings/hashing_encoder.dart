import 'dart:typed_data';

import '../text/text_utils.dart';
import 'text_encoder.dart';
import 'vector_math.dart';

/// Dependency-free fallback encoder: signed feature hashing of word unigrams/bigrams plus
/// character n-grams (fastText-style sub-words). It captures *lexical* similarity and typo /
/// inflection tolerance, but no real semantics - it exists so the app keeps working if the
/// bundled model can't be loaded, and to give tests a deterministic encoder.
class HashingEncoder extends SyncTextEncoder {
  HashingEncoder({this.dim = 256});

  @override
  final int dim;

  @override
  String get id => 'hashing-$dim';

  static int _fnv1a(String s, [int seed = 0x811C9DC5]) {
    var h = seed;
    for (final c in s.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h;
  }

  void _add(Float32List v, String feature, double weight) {
    final h = _fnv1a(feature);
    final sign = (_fnv1a(feature, 0x9747B28C) & 1) == 0 ? 1.0 : -1.0;
    v[h % dim] += sign * weight;
  }

  @override
  Float32List encodeSync(String text) {
    final v = Float32List(dim);
    final words = foldForMatching(text).split(RegExp(r'[^\p{L}\p{N}]+', unicode: true)).where((w) => w.isNotEmpty).toList();
    for (var i = 0; i < words.length; i++) {
      final w = words[i];
      _add(v, 'w:$w', 1.0);
      if (i + 1 < words.length) _add(v, 'b:$w ${words[i + 1]}', 0.6);
      final padded = '<$w>';
      for (var n = 3; n <= 5; n++) {
        for (var s = 0; s + n <= padded.length; s++) {
          _add(v, 'c:${padded.substring(s, s + n)}', 0.35);
        }
      }
    }
    return normalizeInPlace(v);
  }
}
