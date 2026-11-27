import Foundation
import Security

/// The readings the app is showing, handed to the widget.
struct SharedReadings: Codable, Equatable {
    var outdoor: Double?
    var humidity: Double?
    var eco2: Double?
    var tvoc: Double?
    var at: Date
    /// "Live", "Adafruit" or "ThingSpeak"
    var source: String
}

/// What the app hands to the widget: its settings (so the widget can refresh by itself) and its latest readings.
struct WidgetShare: Codable {
    var settings: ConnectionSettings
    var readings: SharedReadings?
}

/// Keychain items the app and the widget may both be able to open.
///
/// The IPA is built unsigned and signed afterwards (Kravasigner), so which Keychain groups the app and the
/// widget get depends on that signing. The app saves the widget's copy in its own group and in a team-wide
/// group ("<team>.nexora.shared"); the widget looks in every group it may open. If the signing keeps them
/// fully apart, the widget falls back to the setup code (see SetupCode).
enum SharedKeychain {
    static let service = "com.aminmigo88.nexora.shared"
    static let account = "widget"

    /// nil when the signing gives this program no Keychain at all.
    static let group: String? = {
        guard let team = teamPrefix() else { return nil }
        return team + ".nexora.shared"
    }()

    /// Status codes of the last read that found nothing, shown small on the widget to diagnose the signing.
    static var lastReadStatus = ""

    /// The team part of this program's own Keychain group ("ABCDE12345.com.aminmigo88.nexora" → "ABCDE12345").
    private static func teamPrefix() -> String? {
        let probe = "com.aminmigo88.nexora.probe"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: probe,
            kSecAttrAccount as String: "team",
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        var status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            let add: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: probe,
                kSecAttrAccount as String: "team",
                kSecValueData as String: Data("team".utf8),
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                kSecReturnAttributes as String: true
            ]
            status = SecItemAdd(add as CFDictionary, &result)
        }
        guard status == errSecSuccess,
              let attributes = result as? [String: Any],
              let accessGroup = attributes[kSecAttrAccessGroup as String] as? String,
              let team = accessGroup.split(separator: ".").first,
              !team.isEmpty else { return nil }
        return String(team)
    }

    static func read() -> WidgetShare? {
        // 1. Every Keychain group this program may open: that includes the app's own group
        //    when the signing gives the app and the widget the same groups.
        let any = copy(group: nil)
        if let data = any.data, let share = try? JSONDecoder().decode(WidgetShare.self, from: data) {
            return share
        }
        // 2. The team-wide group, asked for by name.
        var teamStatus = "no team"
        if let group {
            let shared = copy(group: group)
            teamStatus = String(shared.status)
            if let data = shared.data, let share = try? JSONDecoder().decode(WidgetShare.self, from: data) {
                return share
            }
        }
        // 3. The app's own saved settings (no readings), if this program can open them.
        if let data = Keychain.read(account: "connection"),
           let settings = try? JSONDecoder().decode(ConnectionSettings.self, from: data) {
            return WidgetShare(settings: settings, readings: nil)
        }
        lastReadStatus = "\(any.status) / \(teamStatus)"
        return nil
    }

    private static func copy(group: String?) -> (status: OSStatus, data: Data?) {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        if let group {
            query[kSecAttrAccessGroup as String] = group
        }
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, status == errSecSuccess ? result as? Data : nil)
    }

    /// Saves in this program's own group and in the team-wide group. Returns both statuses.
    @discardableResult
    static func write(_ share: WidgetShare) -> (own: OSStatus, team: OSStatus?) {
        guard let data = try? JSONEncoder().encode(share) else { return (errSecParam, nil) }
        let own = store(data, group: nil)
        let team = group.map { store(data, group: $0) }
        return (own, team)
    }

    private static func store(_ data: Data, group: String?) -> OSStatus {
        var base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if let group {
            base[kSecAttrAccessGroup as String] = group
        }
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        var status = SecItemUpdate(base as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = base
            for (key, value) in attributes {
                add[key] = value
            }
            status = SecItemAdd(add as CFDictionary, nil)
        }
        return status
    }
}

/// The app's settings as one line of text, pasted into the widget (Edit Widget) when the signing
/// keeps the app and the widget apart. It holds the keys, so it only ever goes to this iPhone's clipboard.
enum SetupCode {
    static let prefix = "NXR1."

    static func make(from settings: ConnectionSettings) -> String? {
        guard let data = try? JSONEncoder().encode(settings) else { return nil }
        let body = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return prefix + body
    }

    static func parse(_ text: String?) -> ConnectionSettings? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), trimmed.hasPrefix(prefix) else {
            return nil
        }
        var body = String(trimmed.dropFirst(prefix.count)).filter { !$0.isWhitespace }
        body = body.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while body.count % 4 != 0 {
            body += "="
        }
        guard let data = Data(base64Encoded: body) else { return nil }
        return try? JSONDecoder().decode(ConnectionSettings.self, from: data)
    }
}
