import 'dart:math' as math;
import 'dart:typed_data';

/// Dot product of two equally sized vectors (4x unrolled; the hot loop of search).
double dot(Float32List a, Float32List b) {
  assert(a.length == b.length, 'vector length mismatch: ${a.length} vs ${b.length}');
  final n = a.length;
  var s0 = 0.0, s1 = 0.0, s2 = 0.0, s3 = 0.0;
  var i = 0;
  for (; i + 4 <= n; i += 4) {
    s0 += a[i] * b[i];
    s1 += a[i + 1] * b[i + 1];
    s2 += a[i + 2] * b[i + 2];
    s3 += a[i + 3] * b[i + 3];
  }
  for (; i < n; i++) {
    s0 += a[i] * b[i];
  }
  return s0 + s1 + s2 + s3;
}

/// Dot product of [q] against row [row] of a row-major [matrix] with [dim] columns, starting
/// at column [colOffset] of a row that is [stride] wide.
double dotRow(Float32List matrix, int row, int stride, int colOffset, Float32List q) {
  final base = row * stride + colOffset;
  var s = 0.0;
  for (var i = 0; i < q.length; i++) {
    s += matrix[base + i] * q[i];
  }
  return s;
}

double norm(Float32List a) => math.sqrt(dot(a, a));

/// Normalises [a] to unit length in place (no-op for the zero vector). Returns [a].
Float32List normalizeInPlace(Float32List a) {
  final n = norm(a);
  if (n > 1e-12) {
    final inv = 1.0 / n;
    for (var i = 0; i < a.length; i++) {
      a[i] *= inv;
    }
  }
  return a;
}

Float32List normalized(Float32List a) => normalizeInPlace(Float32List.fromList(a));

/// Cosine similarity; 0 when either vector is (near) zero.
double cosine(Float32List a, Float32List b) {
  final d = norm(a) * norm(b);
  return d < 1e-12 ? 0 : dot(a, b) / d;
}

/// Bounded "keep the best k" collector backed by a binary min-heap.
class TopK<T> {
  TopK(this.k);

  final int k;
  final List<(double, T)> _heap = [];

  int get length => _heap.length;

  /// Smallest score currently kept (or -inf while not full).
  double get threshold => _heap.length < k ? double.negativeInfinity : _heap.first.$1;

  void add(double score, T item) {
    if (_heap.length < k) {
      _heap.add((score, item));
      _siftUp(_heap.length - 1);
    } else if (score > _heap.first.$1) {
      _heap[0] = (score, item);
      _siftDown(0);
    }
  }

  /// Items sorted by descending score.
  List<(double, T)> sorted() => [..._heap]..sort((a, b) => b.$1.compareTo(a.$1));

  void _siftUp(int i) {
    while (i > 0) {
      final p = (i - 1) >> 1;
      if (_heap[p].$1 <= _heap[i].$1) break;
      final t = _heap[p];
      _heap[p] = _heap[i];
      _heap[i] = t;
      i = p;
    }
  }

  void _siftDown(int i) {
    final n = _heap.length;
    while (true) {
      final l = 2 * i + 1, r = l + 1;
      var m = i;
      if (l < n && _heap[l].$1 < _heap[m].$1) m = l;
      if (r < n && _heap[r].$1 < _heap[m].$1) m = r;
      if (m == i) break;
      final t = _heap[m];
      _heap[m] = _heap[i];
      _heap[i] = t;
      i = m;
    }
  }
}

/// Serialises a float vector to bytes (little endian), for SQLite BLOB storage.
Uint8List vectorToBytes(Float32List v) {
  final out = ByteData(v.length * 4);
  for (var i = 0; i < v.length; i++) {
    out.setFloat32(i * 4, v[i], Endian.little);
  }
  return out.buffer.asUint8List();
}

Float32List vectorFromBytes(Uint8List bytes) {
  final bd = ByteData.sublistView(bytes);
  final out = Float32List(bytes.length ~/ 4);
  for (var i = 0; i < out.length; i++) {
    out[i] = bd.getFloat32(i * 4, Endian.little);
  }
  return out;
}
