import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Index of the visible root tab: 0 Capture, 1 Library, 2 Graph, 3 Tasks.
final selectedTabProvider = NotifierProvider<SelectedTab, int>(SelectedTab.new);

class SelectedTab extends Notifier<int> {
  @override
  int build() => 0;

  void select(int index) => state = index;
}

/// A note the Graph tab should centre on and highlight when it becomes visible.
final graphFocusProvider = NotifierProvider<GraphFocus, String?>(GraphFocus.new);

class GraphFocus extends Notifier<String?> {
  @override
  String? build() => null;

  void focus(String? noteId) => state = noteId;
}
