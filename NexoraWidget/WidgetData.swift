import Foundation

/// Everything one widget refresh shows.
struct WidgetData {
    var readings: SharedReadings?
    var outdoorChange: Double?
    var humidityChange: Double?
    var sky: SkyDay
}

enum LoadOutcome {
    case ready(WidgetData)
    /// The app's settings can't be read and there's no setup code; carries the Keychain status codes.
    case needsCode(String)
    /// The pasted setup code doesn't read.
    case badCode
}

/// One widget refresh: readings in the app's order (the ESP32 itself through EMQX, then Adafruit IO,
/// then ThingSpeak), the same time yesterday from ThingSpeak, and today's sun and moon.
enum WidgetLoader {
    private static let lastReadingsKey = "lastReadings"

    static func load(now: Date, code: String?) async -> LoadOutcome {
        // The settings the app handed over (Keychain), else the pasted setup code.
        let settings: ConnectionSettings
        var fromApp: SharedReadings?
        if let share = SharedKeychain.read() {
            settings = share.settings
            fromApp = share.readings
        } else if let parsed = SetupCode.parse(code) {
            settings = parsed
        } else if let code, !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .badCode
        } else {
            return .needsCode(SharedKeychain.lastReadStatus)
        }

        async let skyDay = SkyService.day(for: now, at: SkySpot(settings: settings))
        async let past = Timeout.run(10) { await ThingSpeakNow.yesterday(settings, now: now) }

        var readings: SharedReadings?
        if let fromApp, now.timeIntervalSince(fromApp.at) < 180 {
            // The app was just open: show exactly what it showed.
            readings = fromApp
        } else {
            readings = await ReadingsNow.fetch(settings)
        }
        if readings == nil {
            readings = newest(fromApp, lastReadings())
        }
        if let readings {
            saveLastReadings(readings)
        }

        let sky = await skyDay
        let yesterday = await past
        var data = WidgetData(readings: readings, sky: sky)
        if let current = readings?.outdoor, let then = yesterday?.outdoor {
            data.outdoorChange = current - then
        }
        if let current = readings?.humidity, let then = yesterday?.humidity {
            data.humidityChange = current - then
        }
        return .ready(data)
    }

    private static func newest(_ a: SharedReadings?, _ b: SharedReadings?) -> SharedReadings? {
        guard let a else { return b }
        guard let b else { return a }
        return a.at >= b.at ? a : b
    }

    private static func lastReadings() -> SharedReadings? {
        guard let data = UserDefaults.standard.data(forKey: lastReadingsKey) else { return nil }
        return try? JSONDecoder().decode(SharedReadings.self, from: data)
    }

    private static func saveLastReadings(_ readings: SharedReadings) {
        guard let data = try? JSONEncoder().encode(readings) else { return }
        UserDefaults.standard.set(data, forKey: lastReadingsKey)
    }
}

/// Asks all three sources at once and keeps the best answer, in the app's order.
enum ReadingsNow {
    static func fetch(_ settings: ConnectionSettings) async -> SharedReadings? {
        async let live = Timeout.run(10) { await LiveReadings.fetch(settings) }
        async let adafruit = Timeout.run(10) { await AdafruitReadings.fetch(settings) }
        async let thingSpeak = Timeout.run(10) { await ThingSpeakNow.latest(settings) }
        if let value = await live {
            return value
        }
        if let value = await adafruit {
            return value
        }
        return await thingSpeak
    }
}

/// The ESP32's own /api/info, through EMQX and the relay in the light controller.
@MainActor
enum LiveReadings {
    static func fetch(_ settings: ConnectionSettings) async -> SharedReadings? {
        guard settings.relayConfigured else { return nil }
        let relay = RelayClient()
        var online: Bool?
        relay.onHubStatus = { online = $0 }
        do {
            try await relay.connect(settings)
        } catch {
            return nil
        }
        defer { relay.disconnect() }
        // EMQX sends the relay's retained "online" right after subscribing.
        var waited = 0
        while online == nil && waited < 30 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            waited += 1
        }
        guard online == true,
              let reply = try? await relay.request(method: "GET", path: "/api/info", form: nil),
              reply.status == 200 else { return nil }
        let cleaned = Data(String(decoding: reply.body, as: UTF8.self).utf8)
        guard let info = try? JSONDecoder().decode(StationInfo.self, from: cleaned) else { return nil }
        return SharedReadings(outdoor: info.outdoor, humidity: info.humidity, eco2: info.eco2, tvoc: info.tvoc,
                              at: Date(), source: "Live")
    }
}

/// The last value of the four feeds the widget shows.
enum AdafruitReadings {
    static func fetch(_ settings: ConnectionSettings) async -> SharedReadings? {
        guard settings.adafruitConfigured else { return nil }
        let user = settings.adafruitUser
        let key = settings.adafruitKey
        guard case .success(let keys) = await AdafruitAPI.feedKeys(user: user, key: key, group: settings.adafruitGroupKey) else {
            return nil
        }
        let wanted: [AdafruitFeed] = [.outdoor, .humidity, .eco2, .tvoc]
        var values: [AdafruitFeed: AdafruitReading] = [:]
        await withTaskGroup(of: AdafruitFetch.self) { group in
            for feed in wanted {
                guard let feedKey = keys[feed] else { continue }
                group.addTask {
                    await AdafruitAPI.lastValue(user: user, key: key, feedKey: feedKey, feed: feed)
                }
            }
            for await item in group {
                if let reading = item.reading {
                    values[item.feed] = reading
                }
            }
        }
        guard let newest = values.values.map({ $0.date }).max() else { return nil }
        // A sensor that went offline stops updating its feed: don't show its old value.
        let fresh = values.filter { newest.timeIntervalSince($0.value.date) < 180 }
        return SharedReadings(outdoor: fresh[.outdoor]?.value, humidity: fresh[.humidity]?.value,
                              eco2: fresh[.eco2]?.value, tvoc: fresh[.tvoc]?.value,
                              at: newest, source: "Adafruit")
    }
}

/// ThingSpeak keeps a point every 10 minutes: field 2 humidity, 4 TVOC, 5 eCO₂, 7 outdoor.
enum ThingSpeakNow {
    private struct Feed: Decodable {
        var feeds: [Entry]
    }

    private struct Entry: Decodable {
        var created_at: String
        var field2: String?
        var field4: String?
        var field5: String?
        var field7: String?
    }

    static func latest(_ settings: ConnectionSettings) async -> SharedReadings? {
        guard settings.thingSpeakConfigured,
              let entries = await feeds(settings, extra: [URLQueryItem(name: "results", value: "1")]),
              let last = entries.last,
              let date = parse(last.created_at) else { return nil }
        return SharedReadings(outdoor: number(last.field7), humidity: number(last.field2),
                              eco2: number(last.field5), tvoc: number(last.field4),
                              at: date, source: "ThingSpeak")
    }

    /// Outdoor temperature and humidity at the same time yesterday: the closest points within 15 minutes.
    static func yesterday(_ settings: ConnectionSettings, now: Date) async -> (outdoor: Double?, humidity: Double?)? {
        guard settings.thingSpeakConfigured else { return nil }
        let target = now.addingTimeInterval(-86_400)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let extra = [
            URLQueryItem(name: "start", value: formatter.string(from: target.addingTimeInterval(-900))),
            URLQueryItem(name: "end", value: formatter.string(from: target.addingTimeInterval(900)))
        ]
        guard let entries = await feeds(settings, extra: extra) else { return nil }
        let dated: [(gap: TimeInterval, entry: Entry)] = entries.compactMap { entry in
            guard let date = parse(entry.created_at) else { return nil }
            return (abs(date.timeIntervalSince(target)), entry)
        }
        let outdoor = dated.compactMap { item in number(item.entry.field7).map { (item.gap, $0) } }
            .min { $0.0 < $1.0 }?.1
        let humidity = dated.compactMap { item in number(item.entry.field2).map { (item.gap, $0) } }
            .min { $0.0 < $1.0 }?.1
        return (outdoor, humidity)
    }

    private static func feeds(_ settings: ConnectionSettings, extra: [URLQueryItem]) async -> [Entry]? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.thingspeak.com"
        components.path = "/channels/\(settings.thingSpeakChannel)/feeds.json"
        components.queryItems = [
            URLQueryItem(name: "api_key", value: settings.thingSpeakKey),
            URLQueryItem(name: "round", value: "2")
        ] + extra
        guard let url = components.url else { return nil }
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        guard let result = try? await URLSession.shared.data(for: request),
              (result.1 as? HTTPURLResponse)?.statusCode == 200,
              let feed = try? JSONDecoder().decode(Feed.self, from: result.0) else { return nil }
        return feed.feeds
    }

    private static func parse(_ text: String) -> Date? {
        ISO8601DateFormatter().date(from: text)
    }

    private static func number(_ text: String?) -> Double? {
        guard let text, let value = Double(text.trimmingCharacters(in: .whitespaces)), value.isFinite else { return nil }
        return value
    }
}

/// Runs a step but stops waiting for it after a few seconds, so one slow service can't hold up the widget.
enum Timeout {
    static func run<T>(_ seconds: Double, _ operation: @escaping () async -> T?) async -> T? {
        await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
            let once = Once()
            Task {
                let value = await operation()
                if once.claim() {
                    continuation.resume(returning: value)
                }
            }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                if once.claim() {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

final class Once {
    private let lock = NSLock()
    private var done = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if done {
            return false
        }
        done = true
        return true
    }
}
