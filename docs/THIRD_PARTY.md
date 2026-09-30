# Third-party assets and notices

| Component | Use | License |
|---|---|---|
| [potion-base-8M](https://huggingface.co/minishlab/potion-base-8M) by MinishLab (Model2Vec), distilled from BAAI/bge-base-en-v1.5 | On-device static sentence embeddings; converted to `assets/models/potion-base-8m.psm` by `tool/build_static_model.py` (int8 row-quantised) | MIT |
| [Inter](https://github.com/rsms/inter) v4.1 by Rasmus Andersson | UI typeface (`assets/fonts`, licence text in `OFL-Inter.txt`) | SIL OFL 1.1 |
| Material Design icon paths (`add`, `mic`) | Android tile/widget glyphs (`res/drawable/ic_*.xml`) | Apache-2.0 |
| [`sqlite3.wasm`](https://github.com/simolus3/sqlite3.dart) and [`drift_worker.js`](https://github.com/simolus3/drift) in `web/` | SQLite for the web build (release builds matching the pinned package versions) | MIT |
| Flutter SDK and `cupertino_icons` | Framework, icons | BSD-3-Clause / MIT |
| drift, sqlite3, Riverpod, http, intl, image_picker, speech_to_text, flutter_local_notifications, flutter_secure_storage, shared_preferences, path_provider, url_launcher, quick_actions, timezone | Libraries | BSD / MIT / Apache-2.0 (see each package on pub.dev; `flutter pub deps` lists the full tree) |
| SQLite | Embedded database | Public domain |

The app icon (`assets/branding/icon_master.png`) was generated for this project with an AI image model.

**Project licence:** none has been chosen yet, so by default all rights are reserved. Add a `LICENSE`
file (MIT, Apache-2.0, ...) before inviting contributions.
