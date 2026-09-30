import AppIntents
import SwiftUI
import WidgetKit

// iOS 18 Control Center / lock-screen controls. `OpenURLIntent` opens the deep link in the app.

@available(iOS 18.0, *)
struct QuickNoteControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "app.personalstorage.control.capture") {
            ControlWidgetButton(action: OpenURLIntent(URL(string: "personalstorage:///capture")!)) {
                Label("New note", systemImage: "square.and.pencil")
            }
        }
        .displayName("New note")
        .description("Capture a thought.")
    }
}

@available(iOS 18.0, *)
struct VoiceNoteControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "app.personalstorage.control.voice") {
            ControlWidgetButton(action: OpenURLIntent(URL(string: "personalstorage:///voice")!)) {
                Label("Voice note", systemImage: "mic.fill")
            }
        }
        .displayName("Voice note")
        .description("Dictate a note.")
    }
}
