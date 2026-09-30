# Contributing

## Setup

```bash
# Flutter 3.47.x (Dart 3.13). The CI pins the exact version.
flutter pub get
(cd packages/neural_brain && dart pub get)
dart run build_runner build            # regenerates lib/**/*.g.dart (drift) - they are committed
flutter run                            # iOS/Android device or simulator
```

Web (demo / screenshots): `flutter build web --release`, then serve `build/web` (needs `web/sqlite3.wasm`
and `web/drift_worker.js`, already committed; versions must match `pubspec.lock`).

## Before you push

```bash
dart format $(git ls-files '*.dart' | grep -v '\.g\.dart$')    # page width 120, see analysis_options.yaml
flutter analyze && (cd packages/neural_brain && dart analyze)
(cd packages/neural_brain && dart test)        # ~150 tests, 3 s
flutter test                                   # ~75 tests, ~20 s
```

CI runs exactly this, verifies that generated code is up to date, and builds web and Android.

## Where things go

| Change | Place |
|---|---|
| New language rule, date phrase, verb | `packages/neural_brain/lib/src/nlp` + a test in `packages/neural_brain/test` |
| New concept / vocabulary | `packages/neural_brain/lib/src/ontology/default_ontology.dart`, **bump `defaultOntologyVersion`** |
| Changing scoring weights | `semantic_index.dart` / `concept_mapper.dart`; re-run `brain_quality_test.dart` and read `docs/AI_ENGINE.md` first |
| New table / column | `lib/data/db/tables.dart`, bump `schemaVersion`, add a migration step, re-run build_runner |
| New screen | `lib/features/<name>`; state in `lib/app/providers.dart`; logic in a service, never in the widget |
| Anything visual | use `context.ps` and the widgets in `lib/core/design`; blur only on chrome (see `docs/DESIGN_SYSTEM.md`) |

## Testing rules of thumb

* Put real behaviour under test with the real model and in-memory SQLite; fake only platform services
  (`Reminders`, `MediaStore`, speech).
* In widget tests, drive async database work with `app.run(...)` / `app.seed(...)` (pumps frames until done);
  do not mix in `tester.runAsync` (deadlocks with drift streams). Load the real fonts (`loadAppFonts`) so
  layout assertions reflect production text metrics.
* When tuning the ontology, **do not tune on the held-out sets**: add new notes to a *new* set and report the
  first-run accuracy, as documented in `docs/AI_ENGINE.md`.

## Regenerating assets

| Asset | Command |
|---|---|
| On-device model + parity fixtures | `python tool/build_static_model.py --src <potion-base-8M dir> --out assets/models/potion-base-8m.psm --fixtures packages/neural_brain/test/fixtures/potion_reference.json` |
| Launcher icons (iOS/Android/web) | `python tool/make_icons.py` (from `assets/branding/icon_master.png`) |
| README screenshots | serve `build/web`, then `python tool/web_shots.py [--dark]` |
| iOS widget target | `ruby tool/ios/add_widget_extension.rb` |

## Commits

Conventional style (`feat(scope): ...`, `fix(scope): ...`, `docs: ...`, `test: ...`). Explain *why* in the body.
