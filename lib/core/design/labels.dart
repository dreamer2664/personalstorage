import 'package:neural_brain/neural_brain.dart';

/// Display names for ontology categories ("General" for uncategorised notes).
String categoryLabel(Ontology ontology, String? id) {
  if (id == null) return 'General';
  return ontology[id]?.labelEn ?? id;
}
