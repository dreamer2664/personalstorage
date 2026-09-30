import SwiftUI
import WidgetKit

/// Entry point of the widget extension: lock-screen / home-screen widgets (iOS 16+) and
/// Control Center controls (iOS 18+). Every one of them is a *deep link* into the Flutter app:
///
///     personalstorage:///capture   -> opens the focused composer
///     personalstorage:///voice     -> opens the composer and starts dictation
///
/// Flutter's iOS embedder hands the URL to the Navigator (see `onGenerateRoute` in `lib/app/app.dart`),
/// so no Swift code is needed in the Runner target.
@main
struct PersonalStorageWidgetBundle: WidgetBundle {
    var body: some Widget {
        QuickNoteWidget()
        VoiceNoteWidget()
        if #available(iOS 18.0, *) {
            QuickNoteControl()
            VoiceNoteControl()
        }
    }
}
