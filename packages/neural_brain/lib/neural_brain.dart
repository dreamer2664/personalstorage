/// Pure-Dart, on-device "neural brain": NLP, semantic search and knowledge-graph engine.
///
/// Start with [NeuralBrain] (analysis + query understanding), feed the results into a
/// [SemanticIndex] for hybrid search and related-note discovery, and turn stored notes and edges
/// into a [KnowledgeGraph] that a [ForceLayout] can lay out at 60 fps.
library;

export 'src/analysis/models.dart';
export 'src/analysis/neural_brain.dart';
export 'src/embeddings/cloud_text_encoder.dart';
export 'src/embeddings/hashing_encoder.dart';
export 'src/embeddings/static_text_encoder.dart';
export 'src/embeddings/text_encoder.dart';
export 'src/embeddings/vector_math.dart' show cosine, dot, norm, normalized, vectorFromBytes, vectorToBytes;
export 'src/graph/clustering.dart' show detectCommunities;
export 'src/graph/force_layout.dart';
export 'src/graph/graph_builder.dart';
export 'src/graph/graph_model.dart';
export 'src/index/semantic_index.dart';
export 'src/nlp/action_extractor.dart';
export 'src/nlp/checklist_detector.dart';
export 'src/nlp/datetime_parser.dart';
export 'src/nlp/entity_extractor.dart';
export 'src/nlp/keyword_extractor.dart';
export 'src/nlp/priority_scorer.dart';
export 'src/ontology/concept_mapper.dart';
export 'src/ontology/default_ontology.dart' show defaultOntologyVersion;
export 'src/ontology/ontology.dart';
export 'src/sample/sample_corpus.dart';
export 'src/text/language.dart';
export 'src/text/tokenizer.dart' show Token, Tokenizer;
