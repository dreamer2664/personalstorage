import 'package:flutter/cupertino.dart';

/// Visual identity of a note category (an ontology *domain*).
@immutable
class CategoryStyle {
  const CategoryStyle(this.id, this.icon, this.color);

  final String id;
  final IconData icon;
  final Color color;
}

/// Colours follow the iOS system palette so categories feel native in both appearances.
const Map<String, CategoryStyle> _styles = {
  'shopping': CategoryStyle('shopping', CupertinoIcons.bag_fill, Color(0xFFFF9F0A)),
  'food': CategoryStyle('food', CupertinoIcons.flame_fill, Color(0xFFFF6B35)),
  'health': CategoryStyle('health', CupertinoIcons.heart_fill, Color(0xFFFF375F)),
  'finance': CategoryStyle('finance', CupertinoIcons.money_dollar_circle_fill, Color(0xFF30D158)),
  'work': CategoryStyle('work', CupertinoIcons.briefcase_fill, Color(0xFF5E5CE6)),
  'tech': CategoryStyle('tech', CupertinoIcons.chevron_left_slash_chevron_right, Color(0xFF0A84FF)),
  'learning': CategoryStyle('learning', CupertinoIcons.book_fill, Color(0xFF32ADE6)),
  'travel': CategoryStyle('travel', CupertinoIcons.airplane, Color(0xFF00C7BE)),
  'home': CategoryStyle('home', CupertinoIcons.house_fill, Color(0xFFAC8E68)),
  'people': CategoryStyle('people', CupertinoIcons.person_2_fill, Color(0xFFFF6482)),
  'ideas': CategoryStyle('ideas', CupertinoIcons.lightbulb_fill, Color(0xFFFFD60A)),
  'media': CategoryStyle('media', CupertinoIcons.film_fill, Color(0xFFBF5AF2)),
  'personal': CategoryStyle('personal', CupertinoIcons.sparkles, Color(0xFF63E6BE)),
  'admin': CategoryStyle('admin', CupertinoIcons.doc_text_fill, Color(0xFF8E8E93)),
};

const CategoryStyle generalCategory = CategoryStyle('general', CupertinoIcons.tag_fill, Color(0xFF8E8E93));

/// Style for [categoryId]; notes without a category use the neutral "General" style.
CategoryStyle categoryStyle(String? categoryId) => _styles[categoryId] ?? generalCategory;

/// All styled category ids in display order.
List<String> get allCategoryIds => _styles.keys.toList(growable: false);
