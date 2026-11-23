import Foundation
import Observation

/// Feed keys the firmware's sendToAdafruit() uploads to the group every 20 s.
enum AdafruitFeed: String, CaseIterable, Sendable {
    case indoor = "indoor-probe-temp-ds18b20"
    case outdoor = "outdoor-probe-temp-ds18b20"
    case bmeTemp = "temperature-bme280"
    case humidity
    case pressure
    case eco2
    case tvoc
}

struct AdafruitReading: Equatable, Sendable {
    var value: Double
    var date: Date
}

struct AdafruitFetch: Sendable {
    var feed: AdafruitFeed
    var status: Int
    var reading: AdafruitReading?
}

enum AdafruitError: Error {
    case rejected
    case noGroup(String)
    case noFeeds(String)
    case busy
    case unreadable
    case offline
    case http(Int)

    var message: String {
        switch self {
        case .rejected: return "Adafruit IO didn't accept the username or AIO key."
        case .noGroup(let group): return "Adafruit IO can't find the group \"\(group)\" for this username."
        case .noFeeds(let group): return "The group \"\(group)\" has none of the station's feeds."
        case .busy: return "Adafruit IO asked the app to slow down. Trying again soon."
        case .unreadable: return "Got an answer from Adafruit IO the app couldn't read."
        case .offline: return "Couldn't reach Adafruit IO."
        case .http(let code): return "Adafruit IO answered with error \(code)."
        }
    }
}

private struct AdafruitGroupRecord: Decodable {
    var feeds: [AdafruitFeedRecord]?
}

private struct AdafruitFeedRecord: Decodable {
    var key: String
}

/// One data point from GET .../feeds/{key}/data/last.
private struct AdafruitDataPoint: Decodable {
    var value: String?
    var createdAt: String?
    var createdEpoch: Double?

    enum CodingKeys: String, CodingKey {
        case value
        case createdAt = "created_at"
        case createdEpoch = "created_epoch"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let text = try? c.decodeIfPresent(String.self, forKey: .value) {
            value = text
        } else if let number = try? c.decodeIfPresent(Double.self, forKey: .value) {
            value = String(number)
        } else {
            value = nil
        }
        createdAt = try? c.decodeIfPresent(String.self, forKey: .createdAt)
        createdEpoch = try? c.decodeIfPresent(Double.self, forKey: .createdEpoch)
    }

    var date: Date? {
        if let createdEpoch, createdEpoch > 0 {
            return Date(timeIntervalSince1970: createdEpoch)
        }
        guard let createdAt else { return nil }
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: createdAt) {
            return date
        }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: createdAt)
    }
}

/// Adafruit IO HTTP API v2. Reads only; reading doesn't count against the upload rate limit.
enum AdafruitAPI {
    static let base = "https://io.adafruit.com/api/v2/"

    static func makeRequest(_ path: String, key: String) -> URLRequest? {
        guard let url = URL(string: base + path) else { return nil }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue(key, forHTTPHeaderField: "X-AIO-Key")
        return request
    }

    /// Full keys of the station's feeds in the group, e.g. "room-temperature.humidity".
    static func feedKeys(user: String, key: String, group: String) async -> Result<[AdafruitFeed: String], AdafruitError> {
        let path = FormEncoding.escape(user) + "/groups/" + FormEncoding.escape(group)
        guard let request = makeRequest(path, key: key) else {
            return .failure(.noGroup(group))
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            switch status {
            case 200:
                break
            case 401, 403:
                return .failure(.rejected)
            case 404:
                return .failure(.noGroup(group))
            case 429:
                return .failure(.busy)
            default:
                return .failure(.http(status))
            }
            guard let record = try? JSONDecoder().decode(AdafruitGroupRecord.self, from: data) else {
                return .failure(.unreadable)
            }
            let keys = (record.feeds ?? []).map { $0.key }
            var found: [AdafruitFeed: String] = [:]
            for feed in AdafruitFeed.allCases {
                if let match = keys.first(where: { $0 == feed.rawValue || $0.hasSuffix("." + feed.rawValue) }) {
                    found[feed] = match
                }
            }
            return found.isEmpty ? .failure(.noFeeds(group)) : .success(found)
        } catch {
            return .failure(.offline)
        }
    }

    static func lastValue(user: String, key: String, feedKey: String, feed: AdafruitFeed) async -> AdafruitFetch {
        let path = FormEncoding.escape(user) + "/feeds/" + FormEncoding.escape(feedKey) + "/data/last"
        guard let request = makeRequest(path, key: key) else {
            return AdafruitFetch(feed: feed, status: 0, reading: nil)
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200,
                  let point = try? JSONDecoder().decode(AdafruitDataPoint.self, from: data),
                  let text = point.value,
                  let value = Double(text.trimmingCharacters(in: .whitespaces)),
                  value.isFinite,
                  let date = point.date else {
                return AdafruitFetch(feed: feed, status: status, reading: nil)
            }
            return AdafruitFetch(feed: feed, status: status, reading: AdafruitReading(value: value, date: date))
        } catch {
            return AdafruitFetch(feed: feed, status: 0, reading: nil)
        }
    }
}

/// Live readings for the Overview: the last value of each feed, refreshed every 20 s.
@Observable
@MainActor
final class AdafruitStore {
    private(set) var readings: [AdafruitFeed: AdafruitReading] = [:]
    private(set) var problem: String?
    private(set) var loading = false

    @ObservationIgnored private var feedKeys: [AdafruitFeed: String] = [:]
    @ObservationIgnored private var keysOwner = ""
    @ObservationIgnored private var lastFetch: Date?

    var latestDate: Date? {
        readings.values.map { $0.date }.max()
    }

    func refresh(settings: ConnectionSettings, force: Bool) async {
        guard settings.adafruitConfigured else {
            readings = [:]
            problem = nil
            feedKeys = [:]
            keysOwner = ""
            return
        }
        if loading { return }
        if !force, let lastFetch, Date().timeIntervalSince(lastFetch) < 15 { return }
        loading = true
        defer { loading = false }

        let user = settings.adafruitUser
        let key = settings.adafruitKey
        let group = settings.adafruitGroupKey
        let owner = user + "|" + group
        if owner != keysOwner || feedKeys.isEmpty {
            if owner != keysOwner {
                readings = [:]
            }
            let lookup = await AdafruitAPI.feedKeys(user: user, key: key, group: group)
            switch lookup {
            case .success(let keys):
                feedKeys = keys
                keysOwner = owner
            case .failure(let error):
                problem = error.message
                return
            }
        }

        let targets = feedKeys
        let results = await withTaskGroup(of: AdafruitFetch.self, returning: [AdafruitFetch].self) { taskGroup in
            for (feed, feedKey) in targets {
                taskGroup.addTask {
                    await AdafruitAPI.lastValue(user: user, key: key, feedKey: feedKey, feed: feed)
                }
            }
            var all: [AdafruitFetch] = []
            for await item in taskGroup {
                all.append(item)
            }
            return all
        }

        let statuses = results.map { $0.status }
        if statuses.contains(401) || statuses.contains(403) {
            problem = AdafruitError.rejected.message
            return
        }
        if !statuses.isEmpty && statuses.allSatisfy({ $0 == 404 }) {
            feedKeys = [:]   // the feeds were renamed or deleted; look the group up again next time
        }
        var fresh: [AdafruitFeed: AdafruitReading] = [:]
        for item in results {
            if let reading = item.reading {
                fresh[item.feed] = reading
            }
        }
        guard let newest = fresh.values.map({ $0.date }).max() else {
            problem = statuses.contains(429) ? AdafruitError.busy.message : "Adafruit IO has no readings yet."
            return
        }
        // The firmware skips a sensor that's offline, so its feed stops updating: don't show its old value.
        readings = fresh.filter { newest.timeIntervalSince($0.value.date) < 180 }
        problem = nil
        lastFetch = Date()
    }
}
