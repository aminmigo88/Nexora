import Foundation
import WidgetKit

/// Hands the app's settings and readings to the home screen widget.
@MainActor
enum WidgetBridge {
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
        guard SharedKeychain.write(WidgetShare(settings: settings, readings: shared)) else { return }
        if reload {
            WidgetCenter.shared.reloadAllTimelines()
        }
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
