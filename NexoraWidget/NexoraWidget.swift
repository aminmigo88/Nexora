import SwiftUI
import WidgetKit

@main
struct NexoraWidgetBundle: WidgetBundle {
    var body: some Widget {
        NexoraWidget()
    }
}

struct NexoraWidget: Widget {
    let kind = "NexoraWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NexoraProvider()) { entry in
            NexoraWidgetView(entry: entry)
        }
        .configurationDisplayName("Nexora")
        .description("Outdoor temperature and humidity against yesterday, and the air quality.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

struct NexoraEntry: TimelineEntry {
    enum Status {
        case ready
        case setup
    }

    var date: Date
    var status: Status = .ready
    var readings: SharedReadings?
    var outdoorChange: Double?
    var humidityChange: Double?
    var isDay = false
    var moonPhase = 0.5

    static var sample: NexoraEntry {
        NexoraEntry(date: Date(),
                    readings: SharedReadings(outdoor: 21.8, humidity: 41, eco2: 601, tvoc: 514,
                                             at: Date().addingTimeInterval(-120), source: "Live"),
                    outdoorChange: -2.5, humidityChange: 6, isDay: false, moonPhase: 0.57)
    }
}

struct NexoraProvider: TimelineProvider {
    func placeholder(in context: Context) -> NexoraEntry {
        .sample
    }

    func getSnapshot(in context: Context, completion: @escaping (NexoraEntry) -> Void) {
        if context.isPreview {
            completion(.sample)
            return
        }
        Task {
            completion(await NexoraProvider.entries(now: Date()).first ?? .sample)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NexoraEntry>) -> Void) {
        Task {
            let now = Date()
            let entries = await NexoraProvider.entries(now: now)
            // iOS decides when to refresh (about every 15 to 60 minutes); opening the app refreshes it too.
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(15 * 60))))
        }
    }

    /// One entry every 5 minutes for half an hour, so "updated" and the sun or moon stay right between refreshes.
    static func entries(now: Date) async -> [NexoraEntry] {
        guard let data = await WidgetLoader.load(now: now) else {
            return [NexoraEntry(date: now, status: .setup)]
        }
        return (0..<6).map { step in
            let date = now.addingTimeInterval(Double(step) * 300)
            return NexoraEntry(date: date,
                               readings: data.readings,
                               outdoorChange: data.outdoorChange,
                               humidityChange: data.humidityChange,
                               isDay: data.sky.isDay(at: date),
                               moonPhase: data.sky.moonPhase)
        }
    }
}
