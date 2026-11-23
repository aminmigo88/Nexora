import Foundation

/// GET /api/state on the light controller.
struct LightState: Decodable, Equatable {
    var on: Bool
    var label: String
    var sceneIndex: Int
    var balance: Int
    var brightness: Int
    var r: Int
    var g: Int
    var b: Int
    var type: Int
    var leds: Bool

    /// Static scene showing an RGB color (white channels are off then).
    var isColor: Bool { r != 0 || g != 0 || b != 0 }

    /// True when the warm/cool balance changes what the light shows.
    var usesWhiteBalance: Bool { !isColor && (type == 0 || type == 1) }

    var hex: String { String(format: "%02lx%02lx%02lx", r, g, b) }
}

/// GET /api/ir/state on the light controller.
struct IRState: Decodable, Equatable {
    var mode: String
    var paused: Bool
    var active: Bool
    var index: Int
    var total: Int
    var rateMs: Int
    var elapsedMs: Int
    var tried: IRTried?
    var recv: [String]
    var sent: [IRSent]
}

struct IRTried: Decodable, Equatable {
    var code: String
    var age: Int
}

struct IRSent: Decodable, Equatable {
    var code: String
    var age: Int
    var label: String
}

/// GET /api/remotes on the light controller.
struct RemotesPayload: Codable {
    var remotes: [RemoteProfile]
}

struct RemoteProfile: Codable, Equatable {
    var name: String
    var keys: [RemoteKey]

    /// Always exactly 5 keys, like the firmware.
    func normalized() -> RemoteProfile {
        var copy = self
        if copy.keys.count > 5 {
            copy.keys = Array(copy.keys.prefix(5))
        }
        while copy.keys.count < 5 {
            copy.keys.append(RemoteKey(name: "", orig: "", gen: ""))
        }
        return copy
    }

    /// Keys that translate something: both codes set.
    var mappedCount: Int {
        keys.filter { !$0.orig.isEmpty && !$0.gen.isEmpty }.count
    }
}

struct RemoteKey: Codable, Equatable {
    var name: String
    var orig: String
    var gen: String
}

struct APIErrorBody: Decodable {
    var error: String
}

/// GET /api/info — added in the next firmware update. Every reading is null when its sensor is offline.
struct StationInfo: Decodable, Equatable {
    var version: String?
    var uptime: Int?
    var indoor: Double?
    var outdoor: Double?
    var bmeTemp: Double?
    var humidity: Double?
    var pressure: Double?
    var eco2: Double?
    var tvoc: Double?
    var scenes: [String]?
}

/// What the Overview shows, from the live controller or from ThingSpeak.
struct ReadingsSnapshot {
    var indoor: Double? = nil
    var outdoor: Double? = nil
    var bmeTemp: Double? = nil
    var humidity: Double? = nil
    var pressure: Double? = nil
    var eco2: Double? = nil
    var tvoc: Double? = nil
    var at: Date? = nil
    var live = false
}

enum LogKind: String, CaseIterable, Hashable {
    case system, sensor, light, ir

    var tag: String {
        switch self {
        case .system: return "SYSTEM"
        case .sensor: return "SENSOR"
        case .light: return "LIGHT"
        case .ir: return "IR"
        }
    }

    var title: String {
        switch self {
        case .system: return "System"
        case .sensor: return "Sensor"
        case .light: return "Light"
        case .ir: return "IR"
        }
    }

    static func classify(_ text: String) -> LogKind {
        let line = text.lowercased()
        let ir = ["[ir]", "[remotes]"]
        let light = ["[light]", "[state]", "[pwm]", "[leds]", "temp  warm"]
        let sensor = ["[sensor]", "[ts]", "[ada]", "[baseline]", "indoor probe", "outdoor probe", "bme ", "sgp "]
        if ir.contains(where: { line.hasPrefix($0) }) { return .ir }
        if light.contains(where: { line.hasPrefix($0) }) { return .light }
        if sensor.contains(where: { line.hasPrefix($0) }) { return .sensor }
        return .system
    }
}

struct LogLine: Identifiable, Equatable {
    let id: Int
    let time: Date?
    let text: String
    let kind: LogKind
}

/// The 21 scenes in the firmware's order. /api/info will send the live list.
enum SceneCatalog {
    static let names = [
        "Warm White", "Cool White", "Neutral Mix", "White Steady", "Sunrise", "Sunset",
        "Ocean", "Forest", "Lavender", "Rose", "Deep Red", "Relax RGB", "Party RGB",
        "Movie Night", "Reading", "Breathe", "Candle", "TV", "Police", "Faulty Bulb", "Lightning"
    ]

    static func icon(for name: String) -> String {
        switch name {
        case "Warm White": return "sun.min"
        case "Cool White": return "snowflake"
        case "Neutral Mix": return "circle.lefthalf.filled"
        case "White Steady": return "lightbulb"
        case "Sunrise": return "sunrise"
        case "Sunset": return "sunset"
        case "Ocean": return "water.waves"
        case "Forest": return "leaf"
        case "Lavender": return "camera.macro"
        case "Rose": return "heart"
        case "Deep Red": return "drop.fill"
        case "Relax RGB": return "sofa"
        case "Party RGB": return "party.popper"
        case "Movie Night": return "film"
        case "Reading": return "book"
        case "Breathe": return "wind"
        case "Candle": return "flame"
        case "TV": return "tv"
        case "Police": return "light.beacon.max"
        case "Faulty Bulb": return "lightbulb.slash"
        case "Lightning": return "bolt"
        default: return "sparkles"
        }
    }
}

/// Codes of the light's own IR remote (from the firmware), to label received codes.
enum KnownCodes {
    static let lightRemote: [UInt32: String] = [
        0x00FE5AA5: "On/Off",
        0x00FEDA25: "Warm −",
        0x00FE1AE5: "Cool +",
        0x00FE7A85: "Brightness +",
        0x00FE6A95: "Brightness −",
        0x00FE9F60: "Next scene",
        0x00FE1FE0: "Previous scene",
        0x00FEDF20: "White Steady",
        0x00FECA35: "Full cool"
    ]
}

enum Hex {
    static func parse(_ text: String) -> UInt32? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasPrefix("0x") {
            value.removeFirst(2)
        }
        guard !value.isEmpty, value.count <= 8, value.allSatisfy({ $0.isHexDigit }) else { return nil }
        return UInt32(value, radix: 16)
    }

    static func isValidOrEmpty(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty || parse(value) != nil
    }

    static func string(_ value: UInt32) -> String {
        String(format: "0x%08X", value)
    }
}

enum UTF8Limit {
    /// The firmware keeps names in 20-byte buffers: 19 bytes of UTF-8 plus the end marker.
    static func clamp(_ text: String, _ maxBytes: Int) -> String {
        var out = text
        while out.utf8.count > maxBytes {
            out.removeLast()
        }
        return out
    }
}
