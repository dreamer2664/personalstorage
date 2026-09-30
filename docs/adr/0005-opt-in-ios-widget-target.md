# ADR 0005 - The iOS WidgetKit extension is opt-in

**Status:** accepted

**Context.** The project was developed on Linux: Swift/Xcode code cannot be compiled or run there, while a
compile error in an embedded extension would break *every* iOS build.

**Decision.** Keep the extension's sources in `ios/PersonalStorageWidgets/` but out of the Xcode project. One
idempotent script (`tool/ios/add_widget_extension.rb`, tested against the real project file) adds the target.

**Consequences.** `flutter run` on iOS always works; the lock-screen widgets cost one documented command and a
signing choice. CI builds iOS (non-blocking) and verifies the script; once it has been seen green on a Mac the
script can be run by default.
