import Foundation
import Observation

enum HistoryRange: String, CaseIterable, Identifiable, Hashable {
    case day, week, month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: return "24 h"
        case .week: return "7 days"
        case .month: return "30 days"
        }
    }

    var seconds: TimeInterval {
        switch self {
        case .day: return 86_400
        case .week: return 7 * 86_400
        case .month: return 30 * 86_400
        }
    }

    /// Longer ranges are averaged so the chart stays readable.
    var bucket: TimeInterval? {
        switch self {
        case .day: return nil
        case .week: return 3_600
        case .month: return 3 * 3_600
        }
    }

    var axisFormat: Date.FormatStyle {
        switch self {
        case .day: return .dateTime.hour()
        case .week: return .dateTime.weekday(.abbreviated)
        case .month: return .dateTime.day().month(.abbreviated)
        }
    }
}

/// Readings from ThingSpeak (one point every 10 minutes), kept on the phone for 31 days.
@Observable
@MainActor
final class HistoryStore {
    struct Point: Codable, Hashable, Identifiable {
        var id: Int
        var date: Date
        var indoor: Double?
        var outdoor: Double?
        var bme: Double?
    }

    struct Latest: Codable, Equatable {
        var date: Date
        var bmeTemp: Double?
        var humidity: Double?
        var pressure: Double?
        var tvoc: Double?
        var eco2: Double?
        var indoor: Double?
        var outdoor: Double?
    }

    private struct Cache: Codable {
        var channel: String
        var points: [Point]
        var latest: Latest?
    }

    private struct Feed: Decodable {
        var feeds: [Entry]
    }

    private struct Entry: Decodable {
        var created_at: String
        var entry_id: Int
        var field1: String?
        var field2: String?
        var field3: String?
        var field4: String?
        var field5: String?
        var field6: String?
        var field7: String?
    }

    private(set) var points: [Point]
    private(set) var latest: Latest?
    private(set) var loading = false
    private(set) var problem: String?

    @ObservationIgnored private var channel: String
    @ObservationIgnored private var lastFetch: Date?
    private let fileURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let url = base.appendingPathComponent("thingspeak-history.json")
        fileURL = url
        if let data = try? Data(contentsOf: url), let cache = try? JSONDecoder().decode(Cache.self, from: data) {
            channel = cache.channel
            points = cache.points
            latest = cache.latest
        } else {
            channel = ""
            points = []
            latest = nil
        }
    }

    func refresh(settings: ConnectionSettings, force: Bool) async {
        guard settings.thingSpeakConfigured else {
            problem = nil
            return
        }
        if loading { return }
        if !force, let lastFetch, Date().timeIntervalSince(lastFetch) < 110 { return }
        if settings.thingSpeakChannel != channel {
            points = []
            latest = nil
            channel = settings.thingSpeakChannel
        }

        var days = 31
        if let newest = points.last?.date {
            let gap = Date().timeIntervalSince(newest)
            days = min(31, max(1, Int((gap / 86_400).rounded(.up))))
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.thingspeak.com"
        components.path = "/channels/\(settings.thingSpeakChannel)/feeds.json"
        components.queryItems = [
            URLQueryItem(name: "api_key", value: settings.thingSpeakKey),
            URLQueryItem(name: "days", value: String(days)),
            URLQueryItem(name: "results", value: "8000"),
            URLQueryItem(name: "round", value: "2")
        ]
        guard let url = components.url else {
            problem = "Check the ThingSpeak channel number."
            return
        }

        loading = true
        defer { loading = false }
        do {
            let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200, let feed = try? JSONDecoder().decode(Feed.self, from: data) else {
                problem = status == 200 || status == 400 || status == 404
                    ? "ThingSpeak didn't accept the channel or Read API Key."
                    : "ThingSpeak answered with error \(status)."
                return
            }
            merge(feed.feeds)
            lastFetch = Date()
            problem = nil
            save()
        } catch {
            problem = "Couldn't reach ThingSpeak."
        }
    }

    func series(for range: HistoryRange) -> [Point] {
        let start = Date().addingTimeInterval(-range.seconds)
        let slice = points.filter { $0.date >= start }
        guard let bucket = range.bucket else { return slice }
        var groups: [Int: [Point]] = [:]
        for point in slice {
            let key = Int(point.date.timeIntervalSince1970 / bucket)
            groups[key, default: []].append(point)
        }
        return groups.keys.sorted().map { key in
            let group = groups[key] ?? []
            return Point(id: key,
                         date: Date(timeIntervalSince1970: (Double(key) + 0.5) * bucket),
                         indoor: HistoryStore.average(group.compactMap { $0.indoor }),
                         outdoor: HistoryStore.average(group.compactMap { $0.outdoor }),
                         bme: HistoryStore.average(group.compactMap { $0.bme }))
        }
    }

    private static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func number(_ text: String?) -> Double? {
        guard let text, let value = Double(text.trimmingCharacters(in: .whitespaces)), value.isFinite else { return nil }
        return value
    }

    private func merge(_ entries: [Entry]) {
        let parser = ISO8601DateFormatter()
        var byID: [Int: Point] = [:]
        for point in points {
            byID[point.id] = point
        }
        var newest: Latest?
        for entry in entries {
            guard let date = parser.date(from: entry.created_at) else { continue }
            byID[entry.entry_id] = Point(id: entry.entry_id,
                                         date: date,
                                         indoor: HistoryStore.number(entry.field6),
                                         outdoor: HistoryStore.number(entry.field7),
                                         bme: HistoryStore.number(entry.field1))
            if newest == nil || date > (newest?.date ?? .distantPast) {
                newest = Latest(date: date,
                                bmeTemp: HistoryStore.number(entry.field1),
                                humidity: HistoryStore.number(entry.field2),
                                pressure: HistoryStore.number(entry.field3),
                                tvoc: HistoryStore.number(entry.field4),
                                eco2: HistoryStore.number(entry.field5),
                                indoor: HistoryStore.number(entry.field6),
                                outdoor: HistoryStore.number(entry.field7))
            }
        }
        let cutoff = Date().addingTimeInterval(-31 * 86_400)
        points = byID.values.filter { $0.date >= cutoff }.sorted { $0.date < $1.date }
        if let newest, newest.date >= (latest?.date ?? .distantPast) {
            latest = newest
        }
    }

    private func save() {
        let cache = Cache(channel: channel, points: points, latest: latest)
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
