import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personalstorage/core/design/collage.dart';
import 'package:personalstorage/core/design/glass.dart';
import 'package:personalstorage/core/design/theme.dart';
import 'package:personalstorage/core/design/widgets.dart';
import 'package:personalstorage/core/util/debouncer.dart';
import 'package:personalstorage/core/util/time_format.dart';
import 'package:personalstorage/core/util/ulid.dart';
import 'package:personalstorage/services/reminders.dart';

import 'support/fonts.dart';

Widget _host(Widget child, {Brightness brightness = Brightness.light}) => CupertinoApp(
  theme: buildCupertinoTheme(brightness: brightness),
  builder: (context, c) => PsThemeScope(child: c!),
  home: Center(child: SizedBox(width: 360, child: child)),
);

void main() {
  setUpAll(loadAppFonts);

  group('Ulid', () {
    test('26 chars, sortable by time, strictly increasing within a millisecond', () {
      final at = DateTime.utc(2026, 9, 30, 10);
      final a = Ulid.next(at), b = Ulid.next(at), c = Ulid.next(at.add(const Duration(seconds: 1)));
      expect(a.length, 26);
      expect(a.compareTo(b), lessThan(0));
      expect(b.compareTo(c), lessThan(0));
    });
    test('round-trips its timestamp', () {
      final at = DateTime.fromMillisecondsSinceEpoch(1790000000000);
      expect(Ulid.timeOf(Ulid.next(at)), at);
    });
    test('ids are unique', () {
      expect({for (var i = 0; i < 5000; i++) Ulid.next()}.length, 5000);
    });
  });

  group('TimeFormat', () {
    final now = DateTime(2026, 9, 30, 10);
    test('relative days', () {
      expect(TimeFormat.relativeDay(DateTime(2026, 9, 30), now), 'Today');
      expect(TimeFormat.relativeDay(DateTime(2026, 10, 1), now), 'Tomorrow');
      expect(TimeFormat.relativeDay(DateTime(2026, 9, 29), now), 'Yesterday');
      expect(TimeFormat.relativeDay(DateTime(2026, 10, 3), now), 'Sat');
      expect(TimeFormat.relativeDay(DateTime(2026, 12, 25), now), 'Dec 25');
      expect(TimeFormat.relativeDay(DateTime(2027, 1, 5), now), 'Jan 5, 2027');
    });
    test('due labels include the time only when known', () {
      // Recent ICU data uses a narrow no-break space before AM/PM; compare modulo whitespace.
      String norm(String v) => v.replaceAll(RegExp(r'[\u202f\u00a0]'), ' ');
      expect(norm(TimeFormat.dueLabel(DateTime(2026, 10, 1, 17), now, hasTime: true)), 'Tomorrow, 5:00 PM');
      expect(TimeFormat.dueLabel(DateTime(2026, 10, 1), now, hasTime: false), 'Tomorrow');
    });
    test('ago', () {
      expect(TimeFormat.ago(now.subtract(const Duration(seconds: 10)), now), 'just now');
      expect(TimeFormat.ago(now.subtract(const Duration(minutes: 7)), now), '7m');
      expect(TimeFormat.ago(now.subtract(const Duration(hours: 3)), now), '3h');
      expect(TimeFormat.ago(DateTime(2026, 9, 29, 20), now), 'Yesterday');
    });
  });

  test('Debouncer runs only the latest action', () async {
    final d = Debouncer(const Duration(milliseconds: 20));
    final calls = <int>[];
    for (var i = 0; i < 5; i++) {
      d.run(() => calls.add(i));
    }
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(calls, [4]);
    d.dispose();
  });

  test('notification ids are stable, positive 31-bit values', () {
    final id = LocalNotificationReminders.notificationId('01M3T2N8SY6NN8HX2FSSZDJE9E');
    expect(id, LocalNotificationReminders.notificationId('01M3T2N8SY6NN8HX2FSSZDJE9E'));
    expect(id, inInclusiveRange(0, 0x7FFFFFFF));
    expect(id, isNot(LocalNotificationReminders.notificationId('01M3T2N8SY6NN8HX2FSSZDJE9F')));
  });

  group('design system', () {
    for (final b in Brightness.values) {
      testWidgets('glass panel, chips and buttons render in ${b.name} mode without errors', (t) async {
        await t.pumpWidget(
          _host(
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const GlassPanel(child: SizedBox(height: 40, width: double.infinity)),
                const GlassPanel(blur: false, onTap: null, child: SizedBox(height: 40, width: double.infinity)),
                const PsChip(label: 'Shopping', icon: CupertinoIcons.bag_fill, color: Color(0xFFFF9F0A)),
                PsChip(label: 'filled', filled: true, onRemove: () {}),
                PsButton(
                  label: 'A very long button label that must wrap instead of overflowing the row',
                  icon: CupertinoIcons.sparkles,
                  onPressed: () {},
                ),
                const PsEmptyState(
                  icon: CupertinoIcons.tray,
                  title: 'Nothing here',
                  message: 'A message that explains the empty state.',
                ),
              ],
            ),
            brightness: b,
          ),
        );
        await t.pump(const Duration(milliseconds: 300));
        expect(t.takeException(), isNull, reason: 'no overflow even with a very long label');
      });
    }

    testWidgets('chips are tappable and removable', (t) async {
      var tapped = 0, removed = 0;
      await t.pumpWidget(_host(PsChip(label: 'tag', onTap: () => tapped++, onRemove: () => removed++)));
      await t.tap(find.text('tag'));
      await t.tap(find.byIcon(CupertinoIcons.xmark));
      expect((tapped, removed), (1, 1));
    });

    testWidgets('large accessibility text does not overflow the button', (t) async {
      await t.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2.4)),
          child: _host(PsButton(label: 'Try with sample notes', icon: CupertinoIcons.sparkles, onPressed: () {})),
        ),
      );
      await t.pump();
      expect(t.takeException(), isNull);
    });

    for (var n = 1; n <= 6; n++) {
      testWidgets('photo collage with $n image(s) lays out', (t) async {
        await t.pumpWidget(
          _host(PhotoCollage(paths: [for (var i = 0; i < n; i++) '/nonexistent/$i.jpg'], height: 200)),
        );
        await t.pump();
        expect(t.takeException(), isNull);
        if (n > 4) expect(find.text('+${n - 4}'), findsOneWidget);
      });
    }
  });
}
