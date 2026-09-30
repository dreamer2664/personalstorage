import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:personalstorage/app/app.dart';
import 'package:personalstorage/app/providers.dart';
import 'package:personalstorage/data/db/app_database.dart';
import 'package:personalstorage/services/capture_service.dart';
import 'package:personalstorage/services/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'harness.dart';

/// Everything a widget test needs to run the *real* app tree against an in-memory database,
/// the real bundled model, and fake platform services.
class AppUnderTest {
  AppUnderTest._(this.db, this.prefs, this.reminders, this.container);

  final AppDatabase db;
  final SharedPreferences prefs;
  final FakeReminders reminders;
  final ProviderContainer container;

  AppServices get services => container.read(appServicesProvider).requireValue;

  static Future<AppUnderTest> create({Map<String, Object> prefs = const {}}) async {
    SharedPreferences.setMockInitialValues(prefs);
    final p = await SharedPreferences.getInstance();
    final db = AppDatabase(NativeDatabase.memory());
    final reminders = FakeReminders();
    final modelBytes = Uint8List.fromList(File('assets/models/potion-base-8m.psm').readAsBytesSync());
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(p),
        databaseProvider.overrideWithValue(db),
        modelBytesProvider.overrideWithValue(() => Future.value(modelBytes)),
        remindersProvider.overrideWithValue(reminders),
        mediaStoreProvider.overrideWithValue(FakeMedia()),
        httpClientProvider.overrideWithValue(MockClient((_) async => http.Response('', 404))),
      ],
    );
    return AppUnderTest._(db, p, reminders, container);
  }

  Widget widgetWith({String? initialRoute}) => UncontrolledProviderScope(
    container: container,
    child: PersonalStorageApp(initialRoute: initialRoute),
  );

  /// Pumps the app until the shell is on screen (the splash spins forever, so no pumpAndSettle).
  Future<void> launch(WidgetTester tester, {String? initialRoute}) async {
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(widgetWith(initialRoute: initialRoute));
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (container.read(appServicesProvider).hasValue) break;
    }
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// Runs [action] to completion *inside* the fake-async test zone by pumping frames until it
  /// finishes. (Mixing in `runAsync` deadlocks: drift's streams live in the fake zone and hold the
  /// database lock while waiting for a fake timer that only fires on `pump`.)
  Future<T> run<T>(WidgetTester tester, Future<T> Function() action, {int maxPumps = 3000}) async {
    var done = false;
    late T value;
    Object? error;
    StackTrace? stack;
    action().then(
      (v) {
        value = v;
        done = true;
      },
      onError: (Object e, StackTrace s) {
        error = e;
        stack = s;
        done = true;
      },
    );
    for (var i = 0; i < maxPumps && !done; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    if (!done) throw TimeoutException('action did not finish after $maxPumps pumps');
    if (error != null) Error.throwWithStackTrace(error!, stack!);
    return value;
  }

  /// Captures [texts] (and waits for enrichment) - the equivalent of the user having used the app.
  Future<void> seed(WidgetTester tester, List<String> texts) => run(tester, () async {
    for (final t in texts) {
      await services.capture.capture(CaptureDraft(text: t));
    }
    await services.capture.settle();
  });

  /// Tears the tree down and lets every outstanding timer fire so the test can finish cleanly.
  Future<void> shutdown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 6));
    container.dispose();
    await run(tester, db.close);
  }
}
