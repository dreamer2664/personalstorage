import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

enum VoiceState { idle, starting, listening, unavailable }

/// Dictation wrapper around the platform speech recogniser (`speech_to_text`).
///
/// *Local or cloud* is decided by the operating system: with [preferOnDevice] the recogniser is
/// asked to stay offline (Android/iOS on-device models), otherwise the OS may stream audio to
/// its own cloud service (Google / Apple). The app itself never uploads audio.
class VoiceService extends ChangeNotifier {
  VoiceService({SpeechToText? engine}) : _stt = engine ?? SpeechToText();

  final SpeechToText _stt;
  bool _initialised = false;

  VoiceState _state = VoiceState.idle;
  VoiceState get state => _state;
  bool get isListening => _state == VoiceState.listening || _state == VoiceState.starting;

  /// Normalised microphone level in `[0, 1]` (drives the waveform animation).
  double level = 0;
  String? lastError;
  void Function(String text)? _onFinal;
  String _latest = '';

  void _set(VoiceState s) {
    if (_state == s) return;
    _state = s;
    notifyListeners();
  }

  /// Starts dictation. [onPartial] receives live text, [onDone] the final transcript.
  Future<bool> start({
    required void Function(String text) onPartial,
    required void Function(String text) onDone,
    bool preferOnDevice = false,
    String? localeId,
  }) async {
    if (isListening) return true;
    _set(VoiceState.starting);
    lastError = null;
    _latest = '';
    _onFinal = onDone;
    try {
      if (!_initialised) {
        _initialised = await _stt.initialize(
          onError: (e) {
            lastError = e.errorMsg;
            if (e.permanent) _finish();
          },
          onStatus: (s) {
            if (s == 'done' || s == 'notListening') _finish();
          },
        );
      }
      if (!_initialised) {
        _set(VoiceState.unavailable);
        return false;
      }
      await _stt.listen(
        onResult: (r) {
          _latest = r.recognizedWords;
          onPartial(_latest);
          if (r.finalResult) _finish();
        },
        onSoundLevelChange: (l) {
          // Android reports roughly -2..10 dB, iOS -50..0: squash both into 0..1.
          final v = l > 1 ? (l / 10) : ((l + 50) / 50);
          level = v.clamp(0.0, 1.0);
          notifyListeners();
        },
        listenOptions: SpeechListenOptions(
          partialResults: true,
          onDevice: preferOnDevice,
          cancelOnError: true,
          listenMode: ListenMode.dictation,
          localeId: localeId,
          pauseFor: const Duration(seconds: 4),
          listenFor: const Duration(minutes: 2),
        ),
      );
      _set(VoiceState.listening);
      return true;
    } on Object catch (e) {
      lastError = e.toString();
      _set(VoiceState.unavailable);
      return false;
    }
  }

  /// Ends dictation and delivers the final transcript.
  Future<void> stop() async {
    if (!isListening) return;
    try {
      await _stt.stop();
    } on Object {
      // fall through to _finish
    }
    _finish();
  }

  Future<void> cancel() async {
    _onFinal = null;
    try {
      await _stt.cancel();
    } on Object {
      // ignore
    }
    level = 0;
    _set(VoiceState.idle);
  }

  void _finish() {
    if (_state == VoiceState.idle) return;
    final cb = _onFinal;
    _onFinal = null;
    level = 0;
    _set(VoiceState.idle);
    if (cb != null && _latest.trim().isNotEmpty) cb(_latest.trim());
  }
}
