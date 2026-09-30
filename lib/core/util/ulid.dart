import 'dart:math' as math;

/// Sortable unique ids (ULID): 48-bit millisecond timestamp + 80 bits of randomness, encoded as
/// 26 Crockford-base32 characters. Ids created later sort later - handy for "newest first"
/// without an extra index - and are collision-free across devices, which keeps the door open
/// for sync without re-keying.
class Ulid {
  Ulid._();

  static const String _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  static final math.Random _rnd = math.Random.secure();
  static int _lastTime = -1;
  static final List<int> _lastRandom = List<int>.filled(16, 0);

  /// A new id. Monotonic within the same millisecond.
  static String next([DateTime? at]) {
    final t = (at ?? DateTime.now()).millisecondsSinceEpoch;
    if (t == _lastTime) {
      // Increment the random part so ids stay strictly increasing.
      for (var i = 15; i >= 0; i--) {
        if (_lastRandom[i] < 31) {
          _lastRandom[i]++;
          break;
        }
        _lastRandom[i] = 0;
      }
    } else {
      _lastTime = t;
      for (var i = 0; i < 16; i++) {
        _lastRandom[i] = _rnd.nextInt(32);
      }
    }
    final sb = StringBuffer();
    var time = t;
    final timeChars = List<String>.filled(10, '0');
    for (var i = 9; i >= 0; i--) {
      timeChars[i] = _alphabet[time % 32];
      time ~/= 32;
    }
    sb.writeAll(timeChars);
    for (final r in _lastRandom) {
      sb.write(_alphabet[r]);
    }
    return sb.toString();
  }

  /// Timestamp encoded in [id].
  static DateTime timeOf(String id) {
    var t = 0;
    for (var i = 0; i < 10; i++) {
      t = t * 32 + _alphabet.indexOf(id[i]);
    }
    return DateTime.fromMillisecondsSinceEpoch(t);
  }
}
