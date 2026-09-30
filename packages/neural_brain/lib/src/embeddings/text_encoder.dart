import 'dart:typed_data';

/// Turns text into a dense, L2-normalised vector where *semantic closeness == cosine
/// similarity*. Implementations are interchangeable: the bundled static model, a hashing
/// fallback, or a cloud provider. The [id] is persisted next to every stored vector so the app
/// knows when vectors must be recomputed after the user switches providers.
abstract interface class TextEncoder {
  /// Stable identifier, e.g. `potion-base-8M-int8`. Includes the dimension/version.
  String get id;

  int get dim;

  Future<Float32List> encode(String text);

  Future<List<Float32List>> encodeBatch(List<String> texts);
}

/// An encoder that can answer synchronously (no I/O) - required for zero-latency live hints
/// while the user is typing.
abstract class SyncTextEncoder implements TextEncoder {
  Float32List encodeSync(String text);

  /// How much the model "understands" [text], in `[0, 1]`. Static-embedding models return a
  /// near-random vector for words they don't know, so callers should not trust similarity
  /// scores for low-confidence text. Defaults to fully confident.
  double confidence(String text) => 1.0;

  @override
  Future<Float32List> encode(String text) async => encodeSync(text);

  @override
  Future<List<Float32List>> encodeBatch(List<String> texts) async =>
      [for (final t in texts) encodeSync(t)];
}
