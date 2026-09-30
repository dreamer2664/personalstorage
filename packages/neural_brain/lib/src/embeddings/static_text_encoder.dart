import 'dart:convert';
import 'dart:typed_data';

import 'text_encoder.dart';
import 'vector_math.dart';
import 'wordpiece_tokenizer.dart';

/// On-device sentence embeddings from a **static embedding model** (Model2Vec "potion").
///
/// A static model is a distilled sentence transformer reduced to a token lookup table: the
/// sentence vector is simply the mean of the token vectors. That makes inference ~10^3x cheaper
/// than a transformer (microseconds, no native runtime, no GPU) while keeping most of the
/// semantic quality - a good fit for a capture app that must never block the UI.
///
/// The model is stored in the compact "PSM1" container produced by `tool/build_static_model.py`
/// (int8 row-scaled matrix + vocabulary). See that script for the byte layout.
class StaticTextEncoder extends SyncTextEncoder {
  StaticTextEncoder._({
    required this.id,
    required this.dim,
    required this.tokenizer,
    required Int8List matrix,
    required Float32List scales,
    required this.unkId,
    required this.normalize,
    required this.maxTokens,
  })  : _matrix = matrix,
        _scales = scales,
        vocabSize = scales.length;

  @override
  final String id;
  @override
  final int dim;
  final int vocabSize;
  final int unkId;
  final bool normalize;
  final int maxTokens;
  final WordPieceTokenizer tokenizer;
  final Int8List _matrix;
  final Float32List _scales;

  /// Parses a PSM1 container. Throws [FormatException] for anything unexpected.
  factory StaticTextEncoder.fromBytes(Uint8List bytes) {
    if (bytes.length < 8 || ascii.decode(bytes.sublist(0, 4), allowInvalid: true) != 'PSM1') {
      throw const FormatException('Not a PSM1 static model container');
    }
    final bd = ByteData.sublistView(bytes);
    final headerLen = bd.getUint32(4, Endian.little);
    final header = jsonDecode(utf8.decode(bytes.sublist(8, 8 + headerLen))) as Map<String, Object?>;
    final sections = (header['sections']! as Map<String, Object?>).map(
      (k, v) => MapEntry(k, (v! as List<Object?>).cast<int>()),
    );
    final dim = header['dim']! as int;
    final vocabSize = header['vocab_size']! as int;

    final vocabBytes = Uint8List.sublistView(bytes, sections['vocab']![0], sections['vocab']![0] + sections['vocab']![1]);
    final tokens = utf8.decode(vocabBytes).split('\n');
    if (tokens.length != vocabSize) {
      throw FormatException('Vocabulary size mismatch: ${tokens.length} != $vocabSize');
    }
    final vocab = <String, int>{for (var i = 0; i < tokens.length; i++) tokens[i]: i};

    final scales = Float32List(vocabSize);
    final scaleOffset = sections['scales']![0];
    for (var i = 0; i < vocabSize; i++) {
      scales[i] = bd.getFloat32(scaleOffset + i * 4, Endian.little);
    }
    final matrixOffset = sections['matrix']![0];
    if (sections['matrix']![1] != vocabSize * dim) {
      throw const FormatException('Embedding matrix has unexpected size');
    }
    final matrix = Int8List.sublistView(bytes, matrixOffset, matrixOffset + vocabSize * dim);

    return StaticTextEncoder._(
      id: '${header['name']}-int8',
      dim: dim,
      tokenizer: WordPieceTokenizer(
        vocab: vocab,
        unkId: header['unk_id']! as int,
        continuingPrefix: header['continuing_prefix']! as String,
        maxCharsPerWord: header['max_chars_per_word']! as int,
        lowercase: header['lowercase']! as bool,
        stripAccentsEnabled: header['strip_accents']! as bool,
        handleChineseChars: header['handle_chinese_chars']! as bool,
      ),
      matrix: matrix,
      scales: scales,
      unkId: header['unk_id']! as int,
      normalize: header['normalize']! as bool,
      maxTokens: header['max_tokens']! as int,
    );
  }

  /// Fraction of words the model knows as a single piece (2 pieces count 0.6, more count 0).
  /// Gibberish like "qzxv wkjh" shatters into fragments and scores 0.
  @override
  double confidence(String text) {
    final counts = tokenizer.pieceCounts(text).where((c) => c > 0).toList();
    if (counts.isEmpty) return 0;
    var sum = 0.0;
    for (final c in counts) {
      sum += c == 1 ? 1.0 : (c == 2 ? 0.6 : 0.0);
    }
    return sum / counts.length;
  }

  /// Token ids after dropping `[UNK]` and truncation - exactly what gets pooled.
  List<int> tokenIds(String text) {
    final ids = tokenizer.encode(text).where((i) => i != unkId).toList(growable: false);
    return ids.length > maxTokens ? ids.sublist(0, maxTokens) : ids;
  }

  @override
  Float32List encodeSync(String text) {
    final ids = tokenIds(text);
    final out = Float32List(dim);
    if (ids.isEmpty) return out;
    final acc = Float64List(dim);
    for (final id in ids) {
      final scale = _scales[id];
      final base = id * dim;
      for (var j = 0; j < dim; j++) {
        acc[j] += _matrix[base + j] * scale;
      }
    }
    final inv = 1.0 / ids.length;
    for (var j = 0; j < dim; j++) {
      out[j] = acc[j] * inv;
    }
    return normalize ? normalizeInPlace(out) : out;
  }
}
