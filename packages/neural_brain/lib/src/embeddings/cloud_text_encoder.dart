import 'dart:typed_data';

import 'text_encoder.dart';
import 'vector_math.dart';

/// Minimal HTTP seam so this package stays free of any networking dependency. The app injects
/// an implementation backed by `package:http` (and tests inject a fake).
typedef JsonPost =
    Future<Map<String, Object?>> Function(
      Uri url,
      Map<String, String> headers,
      Map<String, Object?> body,
    );

/// Opt-in cloud embeddings for any **OpenAI-compatible** `/embeddings` endpoint (OpenAI, Azure,
/// Ollama, LM Studio, vLLM ...). Disabled by default - nothing leaves the device unless the
/// user configures a provider in Settings.
class CloudTextEncoder implements TextEncoder {
  CloudTextEncoder({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required this.dim,
    required JsonPost post,
    this.sendDimensions = true,
    this.batchSize = 64,
  }) : _post = post;

  final Uri baseUrl;
  final String apiKey;
  final String model;
  final bool sendDimensions;
  final int batchSize;
  final JsonPost _post;

  @override
  final int dim;

  @override
  String get id => 'cloud:$model:$dim';

  @override
  Future<Float32List> encode(String text) async => (await encodeBatch([text])).single;

  @override
  Future<List<Float32List>> encodeBatch(List<String> texts) async {
    final out = <Float32List>[];
    for (var i = 0; i < texts.length; i += batchSize) {
      final chunk = texts.sublist(i, i + batchSize > texts.length ? texts.length : i + batchSize);
      final response = await _post(
        baseUrl.replace(path: '${baseUrl.path.replaceAll(RegExp(r'/+$'), '')}/embeddings'),
        {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        {
          'model': model,
          'input': [for (final t in chunk) t.trim().isEmpty ? ' ' : t],
          if (sendDimensions) 'dimensions': dim,
        },
      );
      final data = response['data'];
      if (data is! List || data.length != chunk.length) {
        throw StateError('Embedding provider returned an unexpected payload');
      }
      final rows = data.cast<Map<String, Object?>>()
        ..sort((a, b) => ((a['index'] ?? 0) as num).compareTo((b['index'] ?? 0) as num));
      for (final row in rows) {
        final raw = (row['embedding']! as List<Object?>).cast<num>();
        if (raw.length != dim) {
          throw StateError(
            'Provider returned ${raw.length}-d vectors, expected $dim. '
            'Adjust the dimension in Settings.',
          );
        }
        out.add(normalizeInPlace(Float32List.fromList([for (final v in raw) v.toDouble()])));
      }
    }
    return out;
  }
}
