import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quick_actions/quick_actions.dart';

/// Entry points that should drop the user straight into capture: the `personalstorage:///capture`
/// and `///voice` deep links (lock-screen widgets, control centre, Siri), app-icon quick actions,
/// notification taps and the Android share sheet.
enum LaunchActionType { capture, voice, openNote }

@immutable
class LaunchRequest {
  const LaunchRequest(this.type, this.nonce, {this.text, this.imagePaths = const [], this.noteId});

  final LaunchActionType type;

  /// Distinguishes two identical consecutive requests.
  final int nonce;
  final String? text;
  final List<String> imagePaths;
  final String? noteId;
}

final launchRequestProvider = NotifierProvider<LaunchRequestNotifier, LaunchRequest?>(LaunchRequestNotifier.new);

class LaunchRequestNotifier extends Notifier<LaunchRequest?> {
  int _n = 0;

  @override
  LaunchRequest? build() => null;

  void fire(LaunchActionType type, {String? text, List<String> imagePaths = const [], String? noteId}) {
    state = LaunchRequest(type, ++_n, text: text, imagePaths: imagePaths, noteId: noteId);
  }

  void consume() => state = null;
}

/// Wires platform entry points to [launchRequestProvider].
class LaunchActions {
  LaunchActions(this._ref);

  final Ref _ref;
  static const MethodChannel _channel = MethodChannel('app.personalstorage/launch');

  /// Call once at start-up.
  Future<void> attach() async {
    if (kIsWeb) return;
    // 1. Static/dynamic app-icon shortcuts.
    try {
      final qa = const QuickActions();
      await qa.initialize((type) {
        if (type == 'capture') _ref.read(launchRequestProvider.notifier).fire(LaunchActionType.capture);
        if (type == 'voice') _ref.read(launchRequestProvider.notifier).fire(LaunchActionType.voice);
      });
      await qa.setShortcutItems(const [
        ShortcutItem(type: 'capture', localizedTitle: 'New note'),
        ShortcutItem(type: 'voice', localizedTitle: 'Voice note'),
      ]);
    } on Object catch (e) {
      debugPrint('Quick actions unavailable: $e');
    }
    // 2. Android share sheet (text / images) via a tiny native channel.
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onShare') _handleShare(call.arguments);
      return null;
    });
    try {
      _handleShare(await _channel.invokeMethod<Object?>('getInitialShare'));
    } on MissingPluginException {
      // iOS / desktop: nothing to fetch.
    } on Object catch (e) {
      debugPrint('Share channel error: $e');
    }
  }

  void _handleShare(Object? args) {
    if (args is! Map) return;
    final text = args['text'] as String?;
    final images = ((args['images'] as List<Object?>?) ?? const []).whereType<String>().toList();
    if ((text == null || text.trim().isEmpty) && images.isEmpty) return;
    _ref.read(launchRequestProvider.notifier).fire(LaunchActionType.capture, text: text, imagePaths: images);
  }
}
