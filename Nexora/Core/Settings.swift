import Foundation
import Observation
import Security

/// Everything typed in More → Connection. Saved in the iPhone Keychain, never in the app or on GitHub.
struct ConnectionSettings: Codable, Equatable {
    var controllerHost: String = "light-controller.local"
    var emqxHost: String = ""
    var emqxPort: Int = 8084
    var emqxUser: String = ""
    var emqxPassword: String = ""
    var thingSpeakChannel: String = ""
    var thingSpeakKey: String = ""
    var adafruitUser: String = ""
    var adafruitKey: String = ""
    var adafruitGroup: String = "room-temperature"

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        controllerHost = try c.decodeIfPresent(String.self, forKey: .controllerHost) ?? "light-controller.local"
        emqxHost = try c.decodeIfPresent(String.self, forKey: .emqxHost) ?? ""
        emqxPort = try c.decodeIfPresent(Int.self, forKey: .emqxPort) ?? 8084
        emqxUser = try c.decodeIfPresent(String.self, forKey: .emqxUser) ?? ""
        emqxPassword = try c.decodeIfPresent(String.self, forKey: .emqxPassword) ?? ""
        thingSpeakChannel = try c.decodeIfPresent(String.self, forKey: .thingSpeakChannel) ?? ""
        thingSpeakKey = try c.decodeIfPresent(String.self, forKey: .thingSpeakKey) ?? ""
        adafruitUser = try c.decodeIfPresent(String.self, forKey: .adafruitUser) ?? ""
        adafruitKey = try c.decodeIfPresent(String.self, forKey: .adafruitKey) ?? ""
        adafruitGroup = try c.decodeIfPresent(String.self, forKey: .adafruitGroup) ?? "room-temperature"
    }

    var relayConfigured: Bool {
        !emqxHost.isEmpty && !emqxUser.isEmpty && !emqxPassword.isEmpty
    }

    var thingSpeakConfigured: Bool {
        !thingSpeakChannel.isEmpty && !thingSpeakKey.isEmpty
    }

    var adafruitConfigured: Bool {
        !adafruitUser.isEmpty && !adafruitKey.isEmpty
    }

    /// The firmware uploads to "room-temperature" (IO_GROUP in the .ino).
    var adafruitGroupKey: String {
        let group = adafruitGroup.trimmingCharacters(in: .whitespacesAndNewlines)
        return group.isEmpty ? "room-temperature" : group
    }
}

enum Keychain {
    static let service = "com.aminmigo88.nexora"

    static func read(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    static func write(_ data: Data, account: String) -> OSStatus {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
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
        return status
    }
}

@Observable
@MainActor
final class SettingsStore {
    private(set) var value: ConnectionSettings
    /// True only if the Keychain refused to save (a signing problem); then a protected file is used.
    private(set) var usesFileFallback: Bool

    private let fileURL: URL
    private static let account = "connection"

    init() {
        let url = SettingsStore.storageURL()
        fileURL = url
        if let data = Keychain.read(account: SettingsStore.account),
           let saved = try? JSONDecoder().decode(ConnectionSettings.self, from: data) {
            value = saved
            usesFileFallback = false
        } else if let data = try? Data(contentsOf: url),
                  let saved = try? JSONDecoder().decode(ConnectionSettings.self, from: data) {
            value = saved
            usesFileFallback = true
        } else {
            value = ConnectionSettings()
            usesFileFallback = false
        }
    }

    @discardableResult
    func save(_ settings: ConnectionSettings) -> Bool {
        guard let data = try? JSONEncoder().encode(settings) else { return false }
        if Keychain.write(data, account: SettingsStore.account) == errSecSuccess {
            value = settings
            usesFileFallback = false
            try? FileManager.default.removeItem(at: fileURL)
            return true
        }
        do {
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            value = settings
            usesFileFallback = true
            return true
        } catch {
            return false
        }
    }

    private static func storageURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("connection.json")
    }
}
