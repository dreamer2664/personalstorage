import SwiftUI
import WidgetKit

// MARK: - Shared timeline (static content: the widget never needs to refresh)

struct CaptureEntry: TimelineEntry {
    let date: Date
}

struct CaptureProvider: TimelineProvider {
    func placeholder(in context: Context) -> CaptureEntry { CaptureEntry(date: Date()) }

    func getSnapshot(in context: Context, completion: @escaping (CaptureEntry) -> Void) {
        completion(CaptureEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CaptureEntry>) -> Void) {
        completion(Timeline(entries: [CaptureEntry(date: Date())], policy: .never))
    }
}

extension View {
    /// `containerBackground` is iOS 17+; older systems keep the default (transparent) background.
    @ViewBuilder
    func captureWidgetBackground() -> some View {
        if #available(iOS 17.0, *) {
            self.containerBackground(.fill.tertiary, for: .widget)
        } else {
            self
        }
    }
}

// MARK: - Views

struct CaptureWidgetView: View {
    @Environment(\.widgetFamily) private var family

    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: symbol)
                    .font(.title2.weight(.semibold))
            }
        case .accessoryRectangular:
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        case .accessoryInline:
            Label(title, systemImage: symbol)
        default:
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 34, weight: .semibold))
                Text(title).font(.headline)
            }
        }
    }
}

// MARK: - Widgets

struct QuickNoteWidget: Widget {
    let kind = "app.personalstorage.widget.capture"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CaptureProvider()) { _ in
            CaptureWidgetView(symbol: "square.and.pencil", title: "New note", subtitle: "Tap to capture")
                .widgetURL(URL(string: "personalstorage:///capture"))
                .captureWidgetBackground()
        }
        .configurationDisplayName("Quick note")
        .description("Open Personal Storage straight into the composer.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .systemSmall])
    }
}

struct VoiceNoteWidget: Widget {
    let kind = "app.personalstorage.widget.voice"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CaptureProvider()) { _ in
            CaptureWidgetView(symbol: "mic.fill", title: "Voice note", subtitle: "Tap and speak")
                .widgetURL(URL(string: "personalstorage:///voice"))
                .captureWidgetBackground()
        }
        .configurationDisplayName("Voice note")
        .description("Start dictating a note with one tap.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .systemSmall])
    }
}
