import AppIntents
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
        AppIntentConfiguration(kind: kind, intent: NexoraSetupIntent.self, provider: NexoraProvider()) { entry in
            NexoraWidgetView(entry: entry)
        }
        .configurationDisplayName("Nexora")
        .description("Outdoor temperature and humidity against yesterday, and the air quality.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

/// Edit Widget: only needed when the signing keeps the widget from reading the app's settings.
struct NexoraSetupIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Nexora"
    static let description = IntentDescription("Only if the widget asks: paste the code from Nexora → More → Widget → Copy setup code.")

    @Parameter(title: "Setup code")
    var setupCode: String?
}

struct NexoraEntry: TimelineEntry {
    enum Status {
        case ready
        /// Can't read the app's settings and no setup code yet.
        case needsCode
        /// A setup code is there but it doesn't read.
        case badCode
    }

    var date: Date
    var status: Status = .ready
    /// Keychain status codes, shown small when setup is needed.
    var detail = ""
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

struct NexoraProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> NexoraEntry {
        .sample
    }

    func snapshot(for configuration: NexoraSetupIntent, in context: Context) async -> NexoraEntry {
        if context.isPreview {
            return .sample
        }
        return await NexoraProvider.entries(now: Date(), code: configuration.setupCode).first ?? .sample
    }

    func timeline(for configuration: NexoraSetupIntent, in context: Context) async -> Timeline<NexoraEntry> {
        let now = Date()
        let entries = await NexoraProvider.entries(now: now, code: configuration.setupCode)
        // iOS decides when to refresh (about every 15 to 60 minutes); opening the app or editing the widget refreshes it too.
        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(15 * 60)))
    }

    /// One entry every 5 minutes for half an hour, so "updated" and the sun or moon stay right between refreshes.
    static func entries(now: Date, code: String?) async -> [NexoraEntry] {
        switch await WidgetLoader.load(now: now, code: code) {
        case .needsCode(let detail):
            return [setupEntry(now: now, status: .needsCode, detail: detail)]
        case .badCode:
            return [setupEntry(now: now, status: .badCode, detail: "")]
        case .ready(let data):
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

    /// The setup message still sits on the right sky for the time of day.
    private static func setupEntry(now: Date, status: NexoraEntry.Status, detail: String) -> NexoraEntry {
        let sky = SkyMath.day(for: now, spot: SkySpot(settings: ConnectionSettings()))
        return NexoraEntry(date: now, status: status, detail: detail,
                           isDay: sky.isDay(at: now), moonPhase: sky.moonPhase)
    }
}
