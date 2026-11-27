import Foundation
import Security
import WidgetKit

/// Hands the app's settings and readings to the home screen widget.
@MainActor
enum WidgetBridge {
    /// What the last hand-over did, shown in More → Widget: "app ✓ · team ✓", or the Keychain error codes.
    private(set) static var lastStatus = ""

    static func share(settings: ConnectionSettings, readings: ReadingsSnapshot, reload: Bool) {
        var shared: SharedReadings?
        if let at = readings.at, readings.source != .none {
            shared = SharedReadings(outdoor: readings.outdoor, humidity: readings.humidity,
                                    eco2: readings.eco2, tvoc: readings.tvoc, at: at,
                                    source: label(for: readings.source))
        }
        // Nothing new to give: keep the readings the widget already has.
        if shared == nil {
            shared = SharedKeychain.read()?.readings
        }
        let result = SharedKeychain.write(WidgetShare(settings: settings, readings: shared))
        lastStatus = describe(result)
        if reload {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private static func describe(_ result: (own: OSStatus, team: OSStatus?)) -> String {
        let own = result.own == errSecSuccess ? "app ✓" : "app \(result.own)"
        let team: String
        if let status = result.team {
            team = status == errSecSuccess ? "team ✓" : "team \(status)"
        } else {
            team = "no team"
        }
        return own + " · " + team
    }

    private static func label(for source: ReadingsSource) -> String {
        switch source {
        case .controller: return "Live"
        case .adafruit: return "Adafruit"
        case .thingSpeak: return "ThingSpeak"
        case .none: return ""
        }
    }
}
