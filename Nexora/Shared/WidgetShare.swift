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

/// One Keychain item that both the app and the widget can open.
///
/// Its access group is "<team>.nexora.shared". The team prefix is read at run time, because the IPA is
/// built unsigned and signed afterwards (KravaSigner), so it isn't known when the app is built.
enum SharedKeychain {
    static let service = "com.aminmigo88.nexora.shared"
    static let account = "widget"

    /// nil when the signing gives this app no Keychain at all.
    static let group: String? = {
        guard let team = teamPrefix() else { return nil }
        return team + ".nexora.shared"
    }()

    /// The team part of this app's own Keychain access group ("ABCDE12345.com.aminmigo88.nexora" → "ABCDE12345").
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
        guard let group else { return nil }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: group,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(WidgetShare.self, from: data)
    }

    @discardableResult
    static func write(_ share: WidgetShare) -> Bool {
        guard let group, let data = try? JSONEncoder().encode(share) else { return false }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: group
        ]
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
        return status == errSecSuccess
    }
}
