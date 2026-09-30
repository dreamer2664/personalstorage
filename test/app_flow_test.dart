import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personalstorage/app/app.dart';
import 'package:personalstorage/app/navigation.dart';
import 'package:personalstorage/services/launch_actions.dart';
import 'package:personalstorage/services/sample_data.dart';
import 'package:personalstorage/services/settings.dart';

import 'support/app_harness.dart';
import 'support/fonts.dart';

/// Widget tests that run the real app: Riverpod wiring, screens, gestures, database and brain.
///
/// Database work runs through `app.run(...)` / `app.seed(...)`, which pump frames until the work
/// completes (everything stays inside Flutter's fake-async zone).
void main() {
  late AppUnderTest app;

  setUpAll(loadAppFonts);

  setUp(() async {
    app = await AppUnderTest.create();
    // Haptics call a platform channel; swallow it in tests.
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
    // A phone without any speech engine: `initialize` answers "false".
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugin.csdcorp.com/speech_to_text'),
      (call) async => call.method == 'initialize' ? false : null,
    );
  });

  Future<void> type(WidgetTester t, String text) async {
    await t.enterText(find.byType(CupertinoTextField).first, text);
    await t.pump(const Duration(milliseconds: 250));
  }

  Future<void> tapTab(WidgetTester t, String label) async {
    await t.tap(find.text(label).last);
    await t.pump(const Duration(milliseconds: 500));
  }

  /// Lets queued UI-triggered async work (database writes, stream re-emits) finish.
  Future<void> settle(WidgetTester t, {int frames = 12}) async {
    for (var i = 0; i < frames; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  group('capture', () {
    testWidgets('opens on an active composer', (t) async {
      await app.launch(t);
      expect(find.text('Capture a thought…'), findsOneWidget);
      final editable = t.widget<EditableText>(find.byType(EditableText).first);
      expect(editable.focusNode.hasFocus, isTrue, reason: 'zero friction: typing can start immediately');
      await app.shutdown(t);
    });

    testWidgets('typing shows live insights; saving clears the field, stores the note and offers undo', (t) async {
      await app.launch(t);
      await type(t, 'Remind me to call mom tomorrow at 5pm');
      expect(find.textContaining('Call mom'), findsWidgets, reason: 'extracted task chip');
      expect(find.text('People & Social'), findsOneWidget);
      expect(find.text('#mom'), findsOneWidget);

      await t.tap(find.bySemanticsLabel('Save note'));
      await t.pump(const Duration(milliseconds: 100));
      expect(t.widget<CupertinoTextField>(find.byType(CupertinoTextField).first).controller!.text, isEmpty);
      await settle(t);
      expect(find.textContaining('Saved to People & Social'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);

      final notes = await app.run(t, () => app.services.repo.loadSummaries());
      expect(notes, hasLength(1));
      expect(notes.single.openTasks, 1);
      await app.run(t, () => app.services.capture.settle());
      expect(app.reminders.scheduled, hasLength(1), reason: 'a reminder was scheduled for the task');

      await t.tap(find.text('Undo'));
      await settle(t);
      expect(await app.run(t, () => app.services.repo.loadSummaries()), isEmpty);
      await app.shutdown(t);
    });

    testWidgets('"milk and eggs" gets groceries tags and a checklist suggestion that can be accepted', (t) async {
      await app.launch(t);
      await type(t, 'milk and eggs');
      expect(find.text('#groceries'), findsOneWidget);
      expect(find.text('Shopping'), findsOneWidget);
      await t.tap(find.text('Make checklist'));
      await t.pump(const Duration(milliseconds: 200));
      expect(find.textContaining('Checklist · 2 items'), findsOneWidget);
      await t.tap(find.bySemanticsLabel('Save note'));
      await settle(t);
      final n = (await app.run(t, () => app.services.repo.loadSummaries())).single;
      expect(n.checklistTotal, 2);
      await app.shutdown(t);
    });

    testWidgets('the save button does nothing for an empty composer', (t) async {
      await app.launch(t);
      await t.tap(find.bySemanticsLabel('Save note'));
      await settle(t);
      expect(await app.run(t, () => app.services.repo.loadSummaries()), isEmpty);
      await app.shutdown(t);
    });
  });

  group('library & search', () {
    testWidgets('empty library offers sample notes and loads them', (t) async {
      await app.launch(t);
      await tapTab(t, 'Library');
      expect(find.text('Nothing captured yet'), findsOneWidget);
      await t.tap(find.text('Try with sample notes'));
      // Captures are awaited one after another inside the tap handler; pump while they run.
      for (var i = 0; i < 400; i++) {
        await t.pump(const Duration(milliseconds: 50));
        if ((await app.run(t, () => app.services.repo.noteCount())) >= SampleData.count) break;
      }
      expect(await app.run(t, () => app.services.repo.noteCount()), SampleData.count);
      await settle(t, frames: 20);
      expect(find.text('${SampleData.count} notes'), findsOneWidget);
      await app.shutdown(t);
    });

    testWidgets('semantic search: "groceries" finds "milk and eggs"', (t) async {
      await app.launch(t);
      await app.seed(t, ['milk and eggs', 'Fix the login bug in the mobile app']);
      await tapTab(t, 'Library');
      await t.enterText(find.byType(CupertinoTextField).last, 'groceries');
      await settle(t, frames: 40); // debounce (160 ms) + FTS + index search, all driven by pumps
      expect(find.text('Milk and eggs'), findsOneWidget);
      expect(find.text('Fix the login bug in the mobile app'), findsNothing);
      expect(find.textContaining('Concept: Groceries'), findsOneWidget, reason: 'results explain why they matched');
      await app.shutdown(t);
    });

    testWidgets('long-press menu deletes a note and undo restores it', (t) async {
      await app.launch(t);
      await app.seed(t, ['Pay the electricity bill before Friday']);
      await tapTab(t, 'Library');
      await settle(t);
      await t.longPress(find.textContaining('Pay the electricity bill').first);
      await t.pump(const Duration(milliseconds: 400));
      await t.tap(find.text('Delete'));
      await settle(t);
      expect(await app.run(t, () => app.services.repo.loadSummaries()), isEmpty);
      await t.tap(find.text('Undo'));
      await settle(t, frames: 20);
      expect(await app.run(t, () => app.services.repo.loadSummaries()), hasLength(1));
      await app.shutdown(t);
    });
  });

  group('tasks', () {
    testWidgets('extracted tasks are grouped and can be completed', (t) async {
      await app.launch(t);
      await app.seed(t, ['Remind me to call mom tomorrow at 5pm', 'Call the plumber']);
      await tapTab(t, 'Tasks');
      await settle(t);
      expect(find.text('Call mom'), findsOneWidget);
      expect(find.text('NO DATE'), findsOneWidget); // section headers are upper-cased

      final row = find.ancestor(of: find.text('Call the plumber'), matching: find.byType(Row)).first;
      await t.tap(find.descendant(of: row, matching: find.byType(GestureDetector)).first);
      await settle(t);
      final rows = await app.run(t, () => app.services.db.select(app.services.db.tasks).get());
      expect(rows.firstWhere((x) => x.title == 'Call the plumber').done, isTrue);
      expect(rows.firstWhere((x) => x.title == 'Call mom').done, isFalse);
      await app.shutdown(t);
    });
  });

  group('note detail', () {
    testWidgets('shows tags and lets you tick checklist items', (t) async {
      await app.launch(t);
      await app.seed(t, ['Shopping list:\n- olive oil\n- basil']);
      await tapTab(t, 'Library');
      await settle(t);
      await t.tap(find.text('Shopping list').first);
      await settle(t, frames: 16);
      expect(find.textContaining('CHECKLIST'), findsOneWidget);
      expect(find.text('Olive oil'), findsOneWidget);
      await t.tap(find.text('Olive oil'));
      await settle(t);
      final id = (await app.run(t, () => app.services.repo.loadSummaries())).single.id;
      expect((await app.run(t, () => app.services.repo.loadNote(id)))!.checklist.first.checked, isTrue);
      expect(find.text('#groceries'), findsOneWidget);
      await app.shutdown(t);
    });
  });

  group('navigation & launch actions', () {
    testWidgets('the /capture deep link brings the user back to the composer', (t) async {
      await app.launch(t);
      await tapTab(t, 'Tasks');
      expect(app.container.read(selectedTabProvider), 3);
      final nav = t.state<NavigatorState>(find.byType(Navigator).first);
      unawaited(nav.pushNamed('/capture'));
      await settle(t, frames: 10);
      expect(app.container.read(selectedTabProvider), 0, reason: 'deep link selects the Capture tab');
      await app.shutdown(t);
    });

    test('route normalisation understands every form the platforms deliver', () {
      String n(String? s) => PersonalStorageApp.normalizeRoute(s);
      expect(n('/voice'), '/voice');
      expect(n('personalstorage:///voice'), '/voice', reason: 'Android widget / iOS widgetURL (empty host)');
      expect(n('personalstorage://capture'), '/capture', reason: 'host form');
      expect(n('personalstorage:///capture?src=tile'), '/capture');
      expect(n(null), '/');
      expect(n(''), '/');
      expect(n('https://example.com/voice'), '/', reason: 'foreign schemes are never treated as routes');
      expect(n('/some/plain/route'), '/some/plain/route', reason: 'plain route names pass through');
    });

    testWidgets('a cold start from a bare deep-link URI ends up in the app, not on a blank screen', (t) async {
      await app.launch(t, initialRoute: 'personalstorage:///capture');
      await settle(t, frames: 25);
      expect(find.text('Capture a thought…'), findsOneWidget);
      expect(app.container.read(selectedTabProvider), 0);
      await app.shutdown(t);
    });

    testWidgets('a cold start into /voice reaches the composer and tries to start dictation', (t) async {
      await app.launch(t, initialRoute: '/voice');
      await settle(t, frames: 30);
      expect(find.text('Capture a thought…'), findsOneWidget);
      // There is no speech engine in the test VM: the UI must degrade gracefully, not crash.
      expect(find.text('Voice input unavailable'), findsOneWidget);
      await app.shutdown(t);
    });

    testWidgets('a shared text lands in the composer', (t) async {
      await app.launch(t);
      app.container
          .read(launchRequestProvider.notifier)
          .fire(LaunchActionType.capture, text: 'https://example.com/article');
      await settle(t, frames: 10);
      expect(
        t.widget<CupertinoTextField>(find.byType(CupertinoTextField).first).controller!.text,
        contains('https://example.com/article'),
      );
      await app.shutdown(t);
    });
  });

  group('settings', () {
    testWidgets('toggles persist to preferences', (t) async {
      await app.launch(t);
      await tapTab(t, 'Library');
      await t.tap(find.bySemanticsLabel('Settings'));
      await settle(t, frames: 16);
      expect(find.text('NEURAL BRAIN'), findsOneWidget);
      await t.tap(find.text('Dark'));
      await settle(t);
      expect(app.prefs.getString('theme'), ThemeModeSetting.dark.name);
      await app.shutdown(t);
    });
  });
}
