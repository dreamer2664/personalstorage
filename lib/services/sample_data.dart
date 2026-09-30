import 'package:neural_brain/neural_brain.dart';

import 'capture_service.dart';

/// Fills an empty library with the demo corpus (the same notes the tests verify), spread over
/// the last few days so the list, tasks and graph all have something to show.
class SampleData {
  const SampleData._();

  static Future<int> insert(CaptureService capture, {DateTime? now}) async {
    final at = now ?? DateTime.now();
    var n = 0;
    // Oldest first so ULIDs/ordering match the timestamps.
    for (final s in sampleCorpus.reversed) {
      await capture.capture(CaptureDraft(
        text: s.text,
        source: 'sample',
        createdAt: at.subtract(Duration(minutes: s.minutesAgo)),
        referenceTime: at, // reminders are relative to *today*, not to the back-dated timestamp
      ));
      n++;
    }
    return n;
  }

  static int get count => sampleCorpus.length;
}
