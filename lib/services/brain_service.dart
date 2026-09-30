import 'dart:convert';
import 'dart:typed_data';

import 'package:neural_brain/neural_brain.dart';

import '../data/repositories/note_repository.dart';
import '../domain/models.dart';

/// Owns the [NeuralBrain] and the in-memory [SemanticIndex], and translates between analysis
/// results and what gets persisted.
class BrainService {
  BrainService({required this.brain, required this.index});

  final NeuralBrain brain;
  final SemanticIndex index;

  /// Loads the bundled model and builds an empty index. [modelBytes] is injected so tests can
  /// read the asset from disk and the app from `rootBundle`.
  static Future<BrainService> load(
    Future<Uint8List> Function() modelBytes, {
    TextEncoder? retrievalEncoder,
  }) async {
    final encoder = StaticTextEncoder.fromBytes(await modelBytes());
    final brain = NeuralBrain(localEncoder: encoder, retrievalEncoder: retrievalEncoder);
    return BrainService(
      brain: brain,
      index: SemanticIndex(ontology: brain.ontology, calibration: Calibration.forEncoder(brain.retrievalEncoderId)),
    );
  }

  /// Identifier of the vector space notes must be embedded in.
  String get modelId => brain.retrievalEncoderId;
  int get ontologyVersion => brain.ontology.version;

  EmbeddingPayload payload(NoteAnalysis a) => EmbeddingPayload(
        modelId: modelId,
        vector: a.vector,
        conceptsJson: jsonEncode(a.concepts.toSparse()),
        words: a.words.toList(growable: false),
        stems: a.stems.toList(growable: false),
        keywords: [for (final k in a.keywords) k.phrase],
        ontologyVersion: ontologyVersion,
      );

  /// Loads persisted embeddings into the index (only those produced by the current model and
  /// ontology; the rest are refreshed by the enrichment queue).
  Future<int> hydrate(NoteRepository repo) async {
    index.clear();
    var n = 0;
    for (final row in await repo.loadEmbeddings()) {
      if (row.modelId != modelId || row.ontologyVersion != ontologyVersion) continue;
      index.upsert(row.toIndexed(brain.ontology));
      n++;
    }
    return n;
  }
}
